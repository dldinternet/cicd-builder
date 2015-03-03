require 'artifactory'

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
          @properties_matrix = {
              :'build.name'   =>  @vars[:build_mdd][:Project],
              :'build.number' =>  @vars[:build_mdd][:Build],
              :'vcs.revision' =>  @vars[:build_mdd][:Commit]
          }
          @vars[:build_mdd].each do |k,v|
            @properties_matrix["build.#{k.downcase}"] = v
          end
          # matrix = properties.map{|k,v| (v.nil? or v.empty?) ? nil : "#{k}=#{v}"}.join("\;").gsub(%r'^\;*(.*?)\;*$', '\1')
          # @client.endpoint += ";#{matrix}"
          @manifest = {}
          artifacts.each{|art|
            data = art[:data]
            if data.has_key?(:data)
              tempArtifactFile("manifest-#{data[:name]}", data)
            end
            if data.has_key?(:file)
              data[:sha1] = Digest::SHA1.file(data[:file]).hexdigest
              data[:md5]  = Digest::MD5.file(data[:file]).hexdigest
            else
              raise 'Artifact does not have file or data?'
            end
            file_name    = File.basename(data[:file])
            if file_name =~ %r'^#{data[:name]}'
              file_name.gsub!(%r'^#{data[:name]}\.*','')
            end
            file_name.gsub!(%r'\.*-*#{data[:version]}','')
            file_name.gsub!(%r'\.*-*#{data[:build]}-*','')
            file_ext      = file_name.dup
            file_ext.gsub!(%r'^.*?\.*(tar\.gz|tgz|tar\.bzip2|bzip2|tar\.bz2|bz2|jar|war|groovy)$','\1')
            unless file_ext.empty?
              file_name.gsub!(%r'\.*#{file_ext}$','')
            end
            if file_name =~ %r'\.+'
              raise "Unable to parse out file name in #{data[:file]}"
            end
            unless file_name.empty?
              file_name = '_'+file_name.gsub(%r'^(\.|-|)(\w)', '\2').gsub(%r'(\.|-)+', '_')
            end
            maybeUploadArtifactoryObject(data, data[:name], data[:version] || @vars[:version], file_ext, file_name) # -#{@vars[:variant]
            break unless @vars[:return_code] == 0
          }
          if @vars[:return_code] == 0
            manifest_data = ''
            @manifest.each do |k,v|
              manifest_data += "#{k}=#{v}\n"
            end
            data = { data: manifest_data, version: @vars[:build_ver], build: @vars[:build_num], properties: @properties_matrix }
            tempArtifactFile('manifest', data)
            data[:sha1] = Digest::SHA1.file(data[:file]).hexdigest
            data[:md5 ] = Digest::MD5.file(data[:file]).hexdigest
            data[:name] = artifactory_manifest_name
            maybeUploadArtifactoryObject(data, artifactory_manifest_name, data[:version] || @vars[:version], 'properties', '') # -#{@vars[:variant]}
          end
          @vars[:return_code]
        end

        def maybeUploadArtifactoryObject(data, artifact_module, artifact_version, file_ext, file_name)
          artifact_name = getArtifactName(data[:name], file_name, artifact_version, file_ext) # artifact_path = "#{artifactory_org_path()}/#{data[:name]}/#{data[:version]}-#{@vars[:variant]}/#{artifact_name}"
          artifact_path = getArtifactPath(artifact_module, artifact_version, artifact_name)
          objects = maybeArtifactoryObject(artifact_module, artifact_version, false)
          upload = false
          matched = []
          if objects.nil? or objects.size == 0
            upload = true
          else
            @logger.info "#{artifactory_endpoint()}/#{artifactory_repo()}/#{artifact_path} exists - #{objects.size} results"
            @logger.info "\t#{objects.map{|o| o.attributes[:uri]}.join("\t")}"
            matched = matchArtifactoryObjects(artifact_path, data, objects)
            upload ||= (matched.size == 0)
          end
          if upload
            properties_matrix = {}
            data.select{|k,_| not k.to_s.eql?('file')}.each do |k,v|
              properties_matrix["product.#{k}"] = v
            end
            data[:properties] = properties_matrix.merge(@properties_matrix)
            objects = uploadArtifact(artifact_module, artifact_version, artifact_path, data)
            matched = matchArtifactoryObjects(artifact_path, data, objects)
          else
            @logger.info "Keep existing #{matched.map{|o| o.attributes[:uri]}.join("\t")}"
          end
          if data[:temp]
            File.unlink(data[:file])
          end
          @vars[:return_code] = Errors::ARTIFACT_NOT_UPLOADED unless matched.size > 0
          if @vars[:return_code] == 0
            artifact_version += "-#{data[:build] || @vars[:build_num]}"
            artifact_name = getArtifactName(artifact_module, file_name, artifact_version, file_ext, )
            artifact_path = getArtifactPath(artifact_module, artifact_version, artifact_name)
            copies  = maybeArtifactoryObject(artifact_module, artifact_version, false)
            matched = matchArtifactoryObjects(artifact_path, data, copies)
            upload  = (matched.size == 0)
            if upload
              objects.each do |artifact|
                copied = copyArtifact(artifact_module, artifact_version, artifact_path, artifact)
                unless copied.size > 0
                  @vars[:return_code] = Errors::ARTIFACT_NOT_COPIED
                  break
                end
              end
            else
              @logger.info "Keep existing #{matched.map{|o| o.attributes[:uri]}.join("\t")}"
            end
            @manifest[data[:name]] = artifact_version
          end

          @vars[:return_code]
        end

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
        def maybeArtifactoryObject(artifact_name,artifact_version,wide=true)
          begin
            # Get a list of matching artifacts in this repository
            result = @client.artifact_gavc_search(group: artifactory_org_path(), name: artifact_name, version: "#{artifact_version}", repos: [artifactory_repo()])
            if result.size > 0
              @logger.info "Artifactory gavc_search match g=#{artifactory_org_path()},a=#{artifact_name},v=#{artifact_version},r=#{artifactory_repo()}: #{result}"
              # raise "GAVC started working: #{result.ai}"
            elsif wide
              @logger.warn 'GAVC search came up empty!'
              result = @client.artifact_search(name: artifact_name, repos: [artifactory_repo()])
              @logger.info "Artifactory search match a=#{artifact_name},r=#{artifactory_repo()}: #{result}"
            end
            result
          rescue Exception => e
            @logger.error "Artifactory error: #{e.class.name} #{e.message}"
            raise e
          end
        end

        def uploadArtifact(artifact_module, artifact_version, artifact_path, data)
          data[:size] = File.size(data[:file])
          artifact = ::Artifactory::Resource::Artifact.new(local_path: data[:file], client: @client)
          # noinspection RubyStringKeysInHashInspection
          artifact.checksums =  {
                                'md5'   => data[:md5],
                                'sha1'  => data[:sha1],
                                }
          artifact.size = data[:size]
          @logger.info "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}] Start upload #{artifact_path} = #{data[:size]} bytes"
          result = artifact.upload(artifactory_repo(), "#{artifact_path}", data[:properties] || {})
          @logger.info "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}] Uploaded: #{result.attributes.select { |k, _| k != :client }.ai}"
          artifact.upload_checksum(artifactory_repo(), "#{artifact_path}", :sha1, data[:sha1])
          artifact.upload_checksum(artifactory_repo(), "#{artifact_path}", :md5,  data[:md5])
          objects = maybeArtifactoryObject(artifact_module, artifact_version, false)
          unless objects.size > 0
            objects = maybeArtifactoryObject(artifact_module, artifact_version, true)
          end
          raise "Failed to upload '#{artifact_path}'" unless objects.size > 0
          objects
        end

        def copyArtifact(artifact_module, artifact_version, artifact_path, artifact)
          begin
            if artifact.attributes[:uri].eql?(File.join(artifactory_endpoint, artifactory_repo, artifact_path))
              @logger.info "Not copying (identical artifact): #{artifact_path}"
            else
              @logger.info "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}] Start copy #{artifact_path} = #{artifact.attributes[:size]} bytes"
              result = artifact.copy("#{artifactory_repo()}/#{artifact_path}")
              @logger.info "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}] Copied: #{result.ai}"
            end
            objects = maybeArtifactoryObject(artifact_module, artifact_version, false)
            raise "Failed to copy '#{artifact_path}'" unless objects.size > 0
            objects
          rescue Exception => e
            @logger.error "Failed to copy #{artifact_path}: #{e.class.name} #{e.message}"
            raise e
          end
        end

        # ---------------------------------------------------------------------------------------------------------------
        def uploadBuildArtifacts()
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
              @logger.error "#{e.class.name} #{e.message}"
              @vars[:return_code] = Errors::ARTIFACT_UPLOAD_EXCEPTION
              raise e
            end
          else
            @vars[:return_code] = Errors::NO_ARTIFACTS
          end
          @vars[:return_code]
        end

      end
    end
  end
end