require 'json'
require 'semverse'

module CiCd
	module Builder
    # noinspection RubyResolve
    if ENV.has_key?('REPO_TYPE') and (not ENV['REPO_TYPE'].capitalize.equal?('S3'))
      require "cicd/builder/mixlib/repo/#{ENV['REPO_TYPE'].downcase}"
      include const_get("CiCd::Builder::Repo::#{ENV['REPO_TYPE'].capitalize}")
    else
      require 'cicd/builder/mixlib/repo/S3'
      include CiCd::Builder::Repo::S3
    end

    # ---------------------------------------------------------------------------------------------------------------
		def uploadBuildArtifacts()
			if @vars.has_key?(:build_dir) and @vars.has_key?(:build_pkg)
				begin
          artifacts = @vars[:artifacts] rescue []

          key = getKey
          if File.exists?(@vars[:build_pkg])

            # Store the assembly - be sure to inherit possible overrides in pkg name and ext but dictate the drawer!
						artifacts << {
							key:        "#{File.join(File.dirname(key),File.basename(@vars[:build_pkg]))}",
							data:       {:file => @vars[:build_pkg]},
							public_url: :build_url,
							label:      'Package URL'
						}
          else
            # @vars[:return_code] = 1
            @logger.warn "Skipping upload of missing artifact: '#{@vars[:build_pkg]}'"
          end

          # Store the metadata
          manifest = manifestMetadata()
          artifacts << {
            key:        "#{key}.MANIFEST.json",
            data:       {:data => manifest},
            public_url: :manifest_url,
            read_url:   :manifest_url,
            label:      'Manifest URL'
          }

          # Store the checksum
          artifacts << {
            key:        "#{@vars[:project_name]}/#{@vars[:variant]}/#{@vars[:build_nam]}/#{@vars[:build_rel]}.checksum",
            data:       {:data => @vars[:build_sha]},
            public_url: :checksum_url,
            read_url:   :checksum_url,
            label:      'Checksum URL'
          }

          @vars[:return_code] = uploadToRepo(artifacts)
          if 0 == @vars[:return_code]
            @vars[:return_code] = takeInventory()
          end
          @vars[:return_code]
				rescue => e
					@logger.error "#{e.class.name} #{e.message}"
					@vars[:return_code] = -99
					raise e
				end
			else
				@vars[:return_code] = 2
			end
			@vars[:return_code]
		end

    # ---------------------------------------------------------------------------------------------------------------
		def manifestMetadata
			manifest = @vars[:build_mdd].dup

			manifest[:manifest] = getBuilderVersion

			version_major, version_minor, version_patch = manifest[:Version].split('.')

			manifest[:version] = {
				number: manifest[:Version],
				major:  version_major,
				minor:  version_minor,
				patch:  version_patch,
				build:  @vars[:build_num],
				branch: @vars[:build_bra],
			}
			manifest[:build] = {
				name:     @vars[:build_rel],
				base:     @vars[:build_nam],
				date:     @vars[:build_dte],
				vrb:      @vars[:build_vrb],
				branch:   @vars[:build_bra],
				checksum: @vars[:build_sha],
			}
			# we want lowercase but if we use the existing key we don't have to delete it afterwards ...
			manifest[:Release] = {
				number:   manifest[:Release],
				branch:   manifest[:Branch],
				date:     manifest[:Date],
				checksum: @vars[:build_mds],
			}
			manifest.delete(:Date)
			# manifest.delete(:api)
			# manifest.delete(:core)
			manifest[:vars] = {}
			@vars.sort.each { |k, v|
				unless %w(build_mdd build_txt).include?(k.to_s)
					manifest[:vars][k.to_s] = v
				end
			}
			manifest = downcaseHashKeys(manifest)
			manifest[:env] = {}
			ENV.to_hash.sort.each { |k, v|
				unless ENV_IGNORED.include?(k.to_s)
					manifest[:env][k.to_s] = v
				end
			}
      JSON.pretty_generate( manifest, { indent: "\t", space: ' '})
		end

    # ---------------------------------------------------------------------------------------------------------------
    def getArtifactsDefinition()
      nil
    end

    # ---------------------------------------------------------------------------------------------------------------
    def getNamingDefinition()
      nil
    end

  end
end