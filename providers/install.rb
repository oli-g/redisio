#
# Cookbook Name:: redisio
# Provider::install
#
# Copyright 2012, Brian Bianco <brian.bianco@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

action :run do
  @tarball = "#{new_resource.base_name}#{new_resource.version}.#{new_resource.artifact_type}"

  unless ( current_resource.version == new_resource.version || (redis_exists? && new_resource.safe_install) )
    Chef::Log.info("Installing Redis #{new_resource.version} from source")
    download
    unpack
    build
    install
  end
  configure
end

def download
  Chef::Log.info("Downloading redis tarball from #{new_resource.download_url}")
  remote_file "#{new_resource.download_dir}/#{@tarball}" do
    source new_resource.download_url
  end
end

def unpack
  case new_resource.artifact_type
    when "tar.gz",".tgz"
      execute "cd #{new_resource.download_dir} && tar zxf #{@tarball}"
    else
      raise Chef::Exceptions::UnsupportedAction, "Current package type #{new_resource.artifact_type} is unsupported"
  end
end

def build
  execute"cd #{new_resource.download_dir}/#{new_resource.base_name}#{new_resource.version} && make clean && make"
end

def install
  execute "cd #{new_resource.download_dir}/#{new_resource.base_name}#{new_resource.version} && make install"
  new_resource.updated_by_last_action(true)
end

def configure
  #Setup a configuration file and init script for each configuration provided
  new_resource.servers.each do |current_instance|

    #Retrieve the default settings hash and the current server setups settings hash.
    current_instance_hash = current_instance.to_hash
    current_defaults_hash = new_resource.default_settings.to_hash

    #Merge the configuration defaults with the provided array of configurations provided
    current = current_defaults_hash.merge(current_instance_hash)

    #Setup a sub-run-context
    sub_run_context = @run_context.dup
    sub_run_context.resource_collection = Chef::ResourceCollection.new

    begin
      #Set the run_context equal to the sub_run_context that has had its resource collection emptied.
      original_run_context, @run_context = @run_context, sub_run_context

      #Create the owner of the redis data directory
      user current['user'] do
        comment "Redis service account"
        supports :manage_home => true
        home current['homedir']
        shell current['shell']
      end

      #Create the redis configuration directory
      directory current['configdir'] do
        owner 'root'
        group 'root'
        mode "0755"
        action :create
      end
      #Create the instance data directory
      directory current['datadir'] do
        owner current['user']
        group current['group']
        mode "0755"
        action :create
      end
      template "#{current['configdir']}/#{current['port']}.conf" do
        source 'redis.conf.erb'
        owner current['user']
        group current['group']
        mode '0644'
        variables({
          :port                   => current['port'],
          :address                => current['address'],
          :databases              => current['databases'],
          :backuptype             => current['backuptype'],
          :datadir                => current['datadir'],
          :timeout                => current['timeout'],
          :loglevel               => current['loglevel'],
          :save                   => current['save'],
          :slaveof                => current['slaveof'],
          :masterauth             => current['masterauth'],
          :slaveservestaledata    => current['slaveservestaledata'], 
          :replpingslaveperiod    => current['replpingslaveperiod'],
          :repltimeout            => current['repltimeout'],
          :requirepass            => current['requirepass'],
          :maxclients             => current['maxclients'],
          :maxmemory              => current['maxmemory'],
          :maxmemorypolicy        => current['maxmemorypolicy'],
          :maxmemorysamples       => current['maxmemorysamples'],
          :appendfsync            => current['appendfsync'],
          :noappendfsynconrewrite => current['noappendfsynconrewrite'],
          :aofrewritepercentage   => current['aofrewritepercentage'] ,
          :aofrewriteminsize      => current['aofrewriteminsize'],
          :includes               => current['includes']
        })
      end
      #Setup init.d file
      template "/etc/init.d/redis#{current['port']}" do
        source 'redis.init.erb'
        owner 'root'
        group 'root'
        mode '0755'
        variables({
          :port => current['port']
        })
      end
    ensure      
      #now that we are done with the sub run, set the run context back to the original
      @run_context = original_run_context
    end # sub-run-context block end

    # Here we check the resource collection of the sub run to see if anything was updated.  If they were, we called updated by last action on our resource
    begin
      # Converge the sub run, since it is nested it will be converged when the regular run_context is being converged.
      Chef::Runner.new(sub_run_context).converge
    ensure
      if sub_run_context.resource_collection.any?(&:updated?)
        new_resource.updated_by_last_action(true)
      end
    end

  end # servers each loop
end

def redis_exists?
  exists = Chef::ShellOut.new("which redis-server")
  exists.run_command
  exists.exitstatus == 0 ? true : false 
end

def version
  if redis_exists?
    redis_version = Chef::ShellOut.new("redis-server -v | cut -d ' ' -f 4")
    redis_version.run_command
    return redis_version.stdout.gsub("\n",'')
  end
  nil
end

def load_current_resource
  @current_resource = Chef::Resource::RedisioInstall.new(new_resource.name)
  @current_resource.version(version)
  @current_resource
end
