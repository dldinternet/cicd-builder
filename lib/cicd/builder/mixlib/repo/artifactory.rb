require 'artifactory'
require 'artifactory/version'
require 'parallel'
require 'ruby-progressbar'

raise "Need to check compatibility of monkey patch for Artifactory.VERSION == #{::Artifactory::VERSION}" unless ::Artifactory::VERSION == '2.2.1'
module Artifactory
  module Defaults
    class << self
      #
      # Reset all configuration options to their default values.
      #
      # @example Reset all settings
      #   Artifactory.reset!
      #
      # @return [self]
      #
      def reset!
        @_options = nil
        options
      end
      alias_method :setup, :reset!
      #
      # Number of seconds to wait for a response from Artifactory
      #
      # @return [Integer, nil]
      #
      def read_timeout
        ENV['ARTIFACTORY_READ_TIMEOUT'].to_s.to_i || 120
      end
    end
  end
end

module Artifactory
  #
  # A re-usable class containing configuration information for the {Client}. See
  # {Defaults} for a list of default values.
  #
  module Configurable
    #
    # Reset all configuration options to their default values.
    #
    # @example Reset all settings
    #   Artifactory.reset!
    #
    # @return [self]
    #
    def reset!
      Defaults.reset!
      Artifactory::Configurable.keys.each do |key|
        instance_variable_set(:"@#{key}", Defaults.options[key])
      end
      self
    end
    alias_method :setup, :reset!
  end
end

module CiCd
	module Builder
    module Repo
      class Artifactory < CiCd::Builder::Repo::Base
        # include ::Artifactory::Resource

        # ---------------------------------------------------------------------------------------------------------------
        def initialize(builder)
          # Check for the necessary environment variables
          map_keys = {}

          %w[ARTIFACTORY_ENDPOINT ARTIFACTORY_USERNAME ARTIFACTORY_PASSWORD ARTIFACTORY_REPO].each { |k|
            map_keys[k]= (not ENV.has_key?(k) or ENV[k].empty?)
          }
          missing = map_keys.keys.select{ |k| map_keys[k] }

          if missing.count() > 0
            raise("Need these environment variables: #{missing.ai}")
          end

          super(builder)

          # ::Artifactory.configure do |config|
          #   # The endpoint for the Artifactory server. If you are running the "default"
          #   # Artifactory installation using tomcat, don't forget to include the
          #   # +/artifactoy+ part of the URL.
          #   config.endpoint = artifactory_endpoint()
          #
          #   # The basic authentication information. Since this uses HTTP Basic Auth, it
          #   # is highly recommended that you run Artifactory over SSL.
          #   config.username = ENV['ARTIFACTORY_USERNAME']
          #   config.password = ENV['ARTIFACTORY_PASSWORD']
          #
          #   # Speaking of SSL, you can specify the path to a pem file with your custom
          #   # certificates and the gem will wire it all up for you (NOTE: it must be a
          #   # valid PEM file).
          #   # config.ssl_pem_file = '/path/to/my.pem'
          #
          #   # Or if you are feelying frisky, you can always disable SSL verification
          #   # config.ssl_verify = false
          #
          #   # You can specify any proxy information, including any authentication
          #   # information in the URL.
          #   # config.proxy_username = 'user'
          #   # config.proxy_password = 'password'
          #   # config.proxy_address  = 'my.proxy.server'
          #   # config.proxy_port     = '8080'
          # end
          if ENV['ARTIFACTORY_READ_TIMEOUT']
            # [2015-04-29 Christo] Sometimes you just have to shake your head ...
            # a) The Artifactory object does it's setup and read ENV variables during require phase ...
            # b) They do not check if the passed value is valid ( in range or even a number at all ) and they don't convert it to an int
            # c) ENV does not allow one to do this: ENV['ARTIFACTORY_READ_TIMEOUT'] = ENV['ARTIFACTORY_READ_TIMEOUT'].to_s.to_i
            # d) ::Artifactory.setup and ::Artifactory.reset! does not reread those options!!!! OMG!
            # Only resort: Open ::Artifactory class and override the method with the code it should have had ... %)
            ::Artifactory.setup
          end

          @client = ::Artifactory::Client.new()
        end

        # ---------------------------------------------------------------------------------------------------------------
        def method_missing(name, *args)
          if name =~ %r'^artifactory_'
            key = name.to_s.upcase
            raise "ENV has no key #{key}" unless ENV.has_key?(key)
            ENV[key]
          else
            super
          end
        end

        # ---------------------------------------------------------------------------------------------------------------
        def uploadToRepo(artifacts)
          # Set a few build properties on the endpoint URL
          @properties_matrix = {}
          @vars[:build_mdd].each do |k,v|
            @properties_matrix["build.#{k.downcase}"] = v
          end
          # noinspection RubyStringKeysInHashInspection
          @properties_matrix.merge!({
            'build.name'   =>  @vars[:build_mdd][:Project],
            'build.number' =>  @vars[:build_mdd][:Build],
            'build.branch' =>  @vars[:branch],
            'vcs.revision' =>  @vars[:build_mdd][:Commit],
            'vcs.branch'   =>  @vars[:build_mdd][:Branch],
          })
          # @client.endpoint += ";#{matrix}"
          artifacts.each{|art|
            data = art[:data]
            if data.has_key?(:data)
              tempArtifactFile(data[:name], data)
            end
            if data.has_key?(:file)
              data[:sha1] = Digest::SHA1.file(data[:file]).hexdigest
              data[:md5]  = Digest::MD5.file(data[:file]).hexdigest
            else
              raise 'Artifact does not have file or data?'
            end
            file_name, file_ext = (data[:file_name] and data[:file_ext]) ? [data[:file_name], data[:file_ext]] : get_artifact_file_name_ext(data)
            if file_name =~ %r'\.+'
              raise "Unable to parse out file name in #{data[:file]}"
            end
            unless file_name.empty?
              file_name = '_'+file_name.gsub(%r'^(\.|-|)(\w)', '\2').gsub(%r'(\.|-)+', '_')
            end
            maybeUploadArtifactoryObject(data: data, artifact_module: data[:module], artifact_version: data[:version] || @vars[:version], file_name: file_name, file_ext: file_ext) # -#{@vars[:variant]
            break unless @vars[:return_code] == 0
          }
          @vars[:return_code]
        end
        alias_method :cicd_uploadToRepo, :uploadToRepo

        def get_artifact_file_name_ext(data)
          file_name = File.basename(data[:file])
          if file_name =~ %r'^#{data[:name]}'
            file_name.gsub!(%r'^#{data[:name]}\.*', '')
          end
          file_name.gsub!(%r'\.\.+','.')
          file_name.gsub!(%r'\.*-*#{data[:version]}', '')
          file_name.gsub!(%r'\.*-*#{data[:build]}-*', '')
          file_ext = file_name.dup
          file_ext.gsub!(%r'^.*?\.*(tar\.gz|tgz|tar\.bzip2|bzip2|tar\.bz2|bz2|zip|jar|war|groovy)$', '\1')
          unless file_ext.empty?
            file_name.gsub!(%r'\.*#{file_ext}$', '')
          end
          file_name.gsub!(%r'(\.\d+)+$', '')
          return file_name, file_ext
        end

        # ---------------------------------------------------------------------------------------------------------------
        def maybeUploadArtifactoryObject(args)
          data             = args[:data]
          artifact_module  = args[:artifact_module]
          artifact_version = args[:artifact_version]
          file_ext         = args[:file_ext]
          file_name        = args[:file_name]
          make_copy        = (args[:copy].nil? or args[:copy])

          artifact_name = getArtifactName(data[:name], file_name, artifact_version, file_ext) # artifact_path = "#{artifactory_org_path()}/#{data[:name]}/#{data[:version]}-#{@vars[:variant]}/#{artifact_name}"
          artifact_path = getArtifactPath(artifact_module, artifact_version, artifact_name)
          objects = maybeArtifactoryObject(artifact_module, artifact_version, false, args[:repo])
          upload = false
          matched = []
          if objects.nil? or objects.size == 0
            upload = true
          else
            @logger.info "#{artifactory_endpoint()}/#{args[:repo] || artifactory_repo()}/#{artifact_path} exists - #{objects.size} results"
            @logger.info "\t#{objects.map{|o| o.attributes[:uri]}.join("\n\t")}"
            matched = matchArtifactoryObjects(artifact_path, data, objects)
            upload ||= (matched.size == 0)
          end
          if upload
            properties_matrix = {}
            data.select{|k,_| not k.to_s.eql?('file')}.each do |k,v|
              properties_matrix["product.#{k}"] = v
            end
            data[:properties] = properties_matrix.merge(@properties_matrix)
            objects = uploadArtifact(artifact_module, artifact_version, artifact_path, data, args[:repo])
            matched = matchArtifactoryObjects(artifact_path, data, objects)
          else
            @logger.info "Keep existing #{matched.map{|o| o.attributes[:uri]}.join("\t")}"
          end
          if data[:temp]
            if File.exists?(data[:file])
              File.unlink(data[:file]) if File.exists?(data[:file])
              data.delete(:file)
              data.delete(:temp)
            else
              @logger.warn "Temporary file disappeared: #{data.ai}"
            end
          end
          @vars[:return_code] = Errors::ARTIFACT_NOT_UPLOADED unless matched.size > 0
          if @vars[:return_code] == 0 and make_copy
            artifact_version += "-#{data[:build] || @vars[:build_num]}"
            artifact_name = getArtifactName(data[:name], file_name, artifact_version, file_ext, )
            artifact_path = getArtifactPath(artifact_module, artifact_version, artifact_name)
            copies  = maybeArtifactoryObject(artifact_module, artifact_version, false, args[:repo])
            matched = matchArtifactoryObjects(artifact_path, data, copies)
            upload  = (matched.size == 0)
            if upload
              objects.each do |artifact|
                copied = copyArtifact(artifact_module, artifact_version, artifact_path, artifact, args[:repo])
                unless copied.size > 0
                  @vars[:return_code] = Errors::ARTIFACT_NOT_COPIED
                  break
                end
              end
            else
              @logger.info "Keep existing #{matched.map{|o| o.attributes[:uri]}.join("\t")}"
            end
          end
          args[:data]             = data
          args[:artifact_module]  = artifact_module
          args[:artifact_version] = artifact_version
          args[:file_ext]         = file_ext
          args[:file_name]        = file_name

          @vars[:return_code]
        end
        alias_method :cicd_maybeUploadArtifactoryObject, :maybeUploadArtifactoryObject

        def matchArtifactoryObjects(artifact_path, data, objects)
          # matched = false
          objects.select do |artifact|
            @logger.debug "\tChecking: #{artifact.attributes.ai} for #{artifact_path}"
            # if artifact.uri.match(%r'#{artifact_path}$')
            #   @logger.info "\tMatched: #{artifact.attributes.select { |k, _| k != :client }.ai}"
            # end
            matched = (artifact.md5.eql?(data[:md5]) or artifact.sha1.eql?(data[:sha1]))
            matched
          end
        end

        def getArtifactPath(artifact_module, artifact_version, artifact_name)
          artifact_path = "#{artifactory_org_path()}/#{artifact_module}/#{artifact_version}/#{artifact_name}"
        end

        def getArtifactName(name, file_name, artifact_version, file_ext)
          artifact_name = "#{name}#{artifact_version.empty? ? '' : "-#{artifact_version}"}.#{file_ext}" # #{file_name}
        end

        # ---------------------------------------------------------------------------------------------------------------
        def maybeArtifactoryObject(artifact_name,artifact_version,wide=true,repo=nil)
          begin
            # Get a list of matching artifacts in this repository
            @logger.info "Artifactory gavc_search g=#{artifactory_org_path()},a=#{artifact_name},v=#{artifact_version},r=#{repo || artifactory_repo()}"
            @arti_search_result     = []
            monitor(30, 'artifact_gavc_search'){
              @arti_search_result = @client.artifact_gavc_search(group: artifactory_org_path(), name: artifact_name, version: "#{artifact_version}", repos: [repo || artifactory_repo()])
            }
            # noinspection RubyScope
            if @arti_search_result.size > 0
              @logger.info "\tresult: #{@arti_search_result}"
            elsif wide
              @logger.warn 'GAVC search came up empty!'
              @arti_search_result = @client.artifact_search(name: artifact_name, repos: [artifactory_repo()])
              @logger.info "Artifactory search match a=#{artifact_name},r=#{artifactory_repo()}: #{@arti_search_result}"
            end
            @arti_search_result
          rescue Exception => e
            @logger.error "Artifactory error: #{e.class.name} #{e.message}"
            raise e
          end
        end

        # ---------------------------------------------------------------------------------------------------------------
        def latestArtifactoryVersion(artifact_name, repo=nil)
          begin
            # Get a list of matching artifacts in this repository
            @logger.info "Artifactory latest_version g=#{artifactory_org_path()},a=#{artifact_name},r=#{repo || artifactory_repo()}"
            @arti_search_result     = []
            monitor(30, 'artifact_latest_version'){
              @arti_search_result = ::Artifactory::Resource::Artifact.latest_version(client: @client, group: artifactory_org_path(), name: artifact_name, repos: [repo || artifactory_repo()])
            }
            # noinspection RubyScope
            if @arti_search_result and @arti_search_result.size > 0
              @logger.info "\tresult: #{@arti_search_result}"
            end
            @arti_search_result
          rescue Exception => e
            @logger.error "Artifactory error: #{e.class.name} #{e.message}"
            raise e
          end
        end

        def monitor(limit,title='Progress')
          raise 'Must have a block' unless block_given?
          thread = Thread.new(){
            yield
          }
          progressbar = ::ProgressBar.create({title: title, progress_mark: '=', starting_at: 0, total: limit, remainder_mark: '.', throttle_rate: 0.5}) if @logger.info?
          limit.times do
            res = thread.join(1)
            if @logger.info?
              progressbar.increment
              progressbar.total = limit
            end
            unless thread.alive? #or thread.stop?
              puts '' if @logger.info?
              break
            end
          end
          thread.kill if thread.alive? or thread.stop?
        end

        def uploadArtifact(artifact_module, artifact_version, artifact_path, data, repo=nil)
          data[:size] = File.size(data[:file])
          artifact = ::Artifactory::Resource::Artifact.new(local_path: data[:file], client: @client)
          # noinspection RubyStringKeysInHashInspection
          artifact.checksums =  {
                                'md5'   => data[:md5],
                                'sha1'  => data[:sha1],
                                }
          artifact.size = data[:size]
          @logger.info "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}] Start upload #{artifact_path} = #{data[:size]} bytes"
          monitor(30, 'upload') {
            @arti_upload_result = artifact.upload(repo || artifactory_repo(), "#{artifact_path}", data[:properties] || {})
          }
          @logger.info "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}] Uploaded: #{@arti_upload_result.attributes.select { |k, _| k != :client }.ai}"
          3.times{
            @arti_upload_checksum = false
            monitor(30, 'upload_checksum') {
              begin
                artifact.upload_checksum(repo || artifactory_repo(), "#{artifact_path}", :sha1, data[:sha1])
                @arti_upload_checksum = true
              rescue Exception => e
                @logger.fatal "Failed to upload #{artifact_path}: #{e.class.name} #{e.message}"
                raise e
              end
            }
            break if @arti_upload_checksum
          }
          raise "Failed to upload SHA1 for #{artifact_path}" unless @arti_upload_checksum
          3.times{
            @arti_upload_checksum = false
            monitor(30, 'upload_checksum') {
              begin
                artifact.upload_checksum(repo || artifactory_repo(), "#{artifact_path}", :md5,  data[:md5])
                @arti_upload_checksum = true
              rescue Exception => e
                @logger.fatal "Failed to upload #{artifact_path}: #{e.class.name} #{e.message}"
                raise e
              end
            }
            break if @arti_upload_checksum
          }
          raise "Failed to upload MD5 for #{artifact_path}" unless @arti_upload_checksum
          attempt = 0
          objects = []
          while attempt < 3
            objects = maybeArtifactoryObject(artifact_module, artifact_version, false, repo)
            break if objects.size > 0
            sleep 2
            attempt += 1
          end
          raise "Failed to upload '#{artifact_path}'" unless objects.size > 0
          objects
        end

        def copyArtifact(artifact_module, artifact_version, artifact_path, artifact, repo=nil)
          begin
            if artifact.attributes[:uri].eql?(File.join(artifactory_endpoint, repo || artifactory_repo, artifact_path))
              @logger.info "Not copying (identical artifact): #{artifact_path}"
            else
              @logger.info "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}] Start copy #{artifact_path} = #{artifact.attributes[:size]} bytes"
              copied = false
              3.times{
                copied = false
                monitor(30){
                  result = artifact.copy("#{repo || artifactory_repo()}/#{artifact_path}")
                  @logger.info "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}] Copied: #{result.ai}"
                  copied = true
                }
                break if copied
              }
              raise "Failed to copy #{artifact_path}" unless copied
            end
            objects = maybeArtifactoryObject(artifact_module, artifact_version, false, repo)
            unless objects.size > 0
              sleep 10
              objects = maybeArtifactoryObject(artifact_module, artifact_version, false, repo)
              raise "Failed to copy '#{artifact_path}'" unless objects.size > 0
            end
            objects
          rescue Exception => e
            @logger.error "Failed to copy #{artifact_path}: #{e.class.name} #{e.message}"
            raise e
          end
        end

        # ---------------------------------------------------------------------------------------------------------------
        def uploadBuildArtifacts()
          @logger.step CLASS+'::'+__method__.to_s
          if @vars.has_key?(:build_dir) and @vars.has_key?(:build_pkg)
            begin
              artifacts = @vars[:artifacts] rescue []

              key = getKey()
              if File.exists?(@vars[:build_pkg])
                # Store the assembly - be sure to inherit possible overrides in pkg name and ext but dictate the drawer!
                artifacts << {
                    key:        "#{File.join(File.dirname(key),File.basename(@vars[:build_pkg]))}",
                    data:       {:file => @vars[:build_pkg]},
                    public_url: :build_url,
                    label:      'Package URL'
                }
              else
                @logger.warn "Skipping upload of missing artifact: '#{@vars[:build_pkg]}'"
              end

              # Store the metadata
              manifest = manifestMetadata()
              hash     = JSON.parse(manifest)

              @vars[:return_code] = uploadToRepo(artifacts)
              # if 0 == @vars[:return_code]
              #   @vars[:return_code] = takeInventory()
              # end
              @vars[:return_code]
            rescue => e
              @logger.error "#{e.class.name} #{e.message}\n#{e.backtrace.ai}"
              @vars[:return_code] = Errors::ARTIFACT_UPLOAD_EXCEPTION
              raise e
            end
          else
            @vars[:return_code] = Errors::NO_ARTIFACTS
          end
          @vars[:return_code]
        end

        # ---------------------------------------------------------------------------------------------------------------
        def cleanupTempFiles
          @vars[:artifacts].each do |art|
            if art[:data][:temp].is_a?(FalseClass)
              if File.exists?(art[:data][:file])
                File.unlink(art[:data][:file]) if File.exists?(art[:data][:file])
                art[:data].delete(:file)
                art[:data].delete(:temp)
              else
                @logger.warn "Temporary file disappeared: #{data.ai}"
                @vars[:return_code] = Errors::TEMP_FILE_MISSING
              end
            end
          end
        end

      end
    end
  end
end