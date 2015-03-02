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
          manifest = {}
          artifacts.each{|art|
            data = art[:data]
            objects = maybeArtifactoryObject(data)
            upload = false
            if data.has_key?(:data)
              tempArtifactFile("manifest-#{data[:name]}", data)
            end
            if data.has_key?(:file)
              sha1 = Digest::SHA1.file(data[:file]).hexdigest
              md5  = Digest::MD5.file(data[:file]).hexdigest
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
            unless file_name.empty? or file_name.match(%r'^-')
              file_name = "-#{file_name}"
            end
            artifact_name = "#{data[:name]}-#{data[:version]}#{file_name}-#{data[:build]}.#{file_ext}" # -#{@vars[:variant]}
            artifact_path = "#{artifactory_org_path()}/#{data[:name]}/#{data[:version]}-#{@vars[:variant]}/#{artifact_name}"
            manifest[data[:name]] = artifact_path
            if objects.nil? or objects.size == 0
              upload = true
            else
              @logger.info "#{artifactory_endpoint()}/#{artifactory_repo()}/#{artifact_path} exists - #{objects.size} results"
              # Check the checksum of the artifact
              matched = false
              objects.each do |artifact|
                @logger.debug "\tChecking: #{artifact.attributes.ai} for #{artifact_path}"
                if artifact.uri.match(%r'#{artifact_path}$')
                  matched = true
                  @logger.info "\tMatched: #{artifact.attributes.select{|k,_| k != :client}.ai}"
                  if artifact.md5 != md5 or artifact.sha1 != sha1
                    upload = true
                  end
                end
              end
              upload ||= (not matched)
            end

            if upload
              data[:properties] = @properties_matrix
              uploadArtifact(artifact_path, data, md5, sha1)
            else
              @logger.info "Keep existing #{artifactory_endpoint()}/#{artifact_path}"
            end
            if data[:temp]
              File.unlink(data[:file])
            end
          }
          manifest_data = ''
          manifest.each do |k,v|
            manifest_data += "#{k}=#{v}\n"
          end
          data = { data: manifest_data, version: @vars[:build_ver], build: @vars[:build_num], properties: @properties_matrix }
          tempArtifactFile('manifest', data)
          sha1 = Digest::SHA1.file(data[:file]).hexdigest
          md5  = Digest::MD5.file(data[:file]).hexdigest
          artifact_name = "#{artifactory_manifest_name}-#{data[:version]}-#{data[:build]}.properties"
          artifact_path = "#{artifactory_org_path()}/#{artifactory_manifest_module}/#{data[:version]}-#{@vars[:variant]}/#{artifact_name}"
          uploadArtifact(artifact_path, data, md5, sha1)
          if data[:temp]
            File.unlink(data[:file])
          end
          0
        end

        def uploadArtifact(artifact_path, data, md5, sha1)
          data[:size] = File.size(data[:file])
          @logger.info "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}] Start upload #{artifact_path} = #{data[:size]} bytes"
          artifact = ::Artifactory::Resource::Artifact.new(local_path: data[:file], client: @client)
          # noinspection RubyStringKeysInHashInspection
          artifact.checksums =  {
                                'md5'   => md5,
                                'sha1'  => sha1
                                }
          artifact.size = data[:size]
          result = artifact.upload(artifactory_repo(), "#{artifact_path}", data[:properties] || {})
          @logger.info "[#{Time.now.strftime('%Y-%m-%d %H:%M:%S %z')}] Uploaded: #{result.attributes.select { |k, _| k != :client }.ai}"
          artifact.upload_checksum(artifactory_repo(), "#{artifact_path}", :sha1, sha1)
          artifact.upload_checksum(artifactory_repo(), "#{artifact_path}", :md5, md5)
          objects = maybeArtifactoryObject(data, false)
          raise "Failed to upload '#{artifact_path}'" unless objects.size > 0
        end

        def maybeArtifactoryObject(data,wide=true)
          begin
            # Get a list of matching artifacts in this repository
            result = @client.artifact_gavc_search(group: artifactory_org_path(), name: data[:name], version: "#{data[:version]}-#{@vars[:variant]}", repos: [artifactory_repo()])
            if result.size > 0
              @logger.info "Artifactory gavc_search match g=#{artifactory_org_path()},a=#{data[:name]},v=#{data[:version]}-#{@vars[:variant]},r=#{artifactory_repo()}: #{result}"
              # raise "GAVC started working: #{result.ai}"
            elsif wide
              @logger.warn 'GAVC search came up empty!'
              result = @client.artifact_search(name: data[:name], repos: [artifactory_repo()])
              @logger.info "Artifactory search match a=#{data[:name]},r=#{artifactory_repo()}: #{result}"
            end
            result
          rescue Exception => e
            @logger.error "Artifactory error: #{e.class.name} #{e.message}"
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