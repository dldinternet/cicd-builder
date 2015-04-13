require 'json'
require 'semverse'

module CiCd
	module Builder
    require 'cicd/builder/mixlib/repo/base'
    require 'cicd/builder/mixlib/repo/S3'
    # noinspection RubyResolve
    if ENV.has_key?('REPO_TYPE') and (not ENV['REPO_TYPE'].capitalize.eql?('S3'))
      require "cicd/builder/mixlib/repo/#{ENV['REPO_TYPE'].downcase}"
    end

    # ---------------------------------------------------------------------------------------------------------------
		def getRepoClass(type = nil)
      @logger.info __method__.to_s
      if type.nil?
        type ||= 'S3'
        if ENV.has_key?('REPO_TYPE')
          type = ENV['REPO_TYPE']
        end
      end

      @logger.info "#{type} repo interface"
      clazz = Object.const_get("CiCd::Builder::Repo::#{type}")
      if block_given?
        if clazz.is_a?(Class) and not clazz.nil?
          yield
        end
      end

      clazz
    end

    # ---------------------------------------------------------------------------------------------------------------
    def performOnRepoInstance(verb)
      @logger.step __method__.to_s
      clazz = getRepoClass()
      if clazz.is_a?(Class) and not clazz.nil?
        @repo = clazz.new(self)
        method = @repo.method(verb)
        if method.owner == clazz
          @vars[:return_code] = @repo.send(verb)
        else
          @logger.error "#{clazz.name.to_s} cannot do action #{verb}"
          @vars[:return_code] = Errors::BUILDER_REPO_ACTION
        end
      else
        @logger.error "#{clazz.name.to_s} is not a valid repo class"
        @vars[:return_code] = Errors::BUILDER_REPO_TYPE
      end
      @vars[:return_code]
    end

    # ---------------------------------------------------------------------------------------------------------------
    def uploadBuildArtifacts()
      @logger.step __method__.to_s
      performOnRepoInstance(__method__.to_s)
    end

    # ---------------------------------------------------------------------------------------------------------------
    def analyzeInventory()
      @logger.step __method__.to_s
			performOnRepoInstance(__method__.to_s)
    end

    # ---------------------------------------------------------------------------------------------------------------
    def pruneInventory()
      @logger.step __method__.to_s
			performOnRepoInstance(__method__.to_s)
    end

    # ---------------------------------------------------------------------------------------------------------------
    def syncInventory()
      @logger.step __method__.to_s
			performOnRepoInstance(__method__.to_s)
    end

    # ---------------------------------------------------------------------------------------------------------------
    def syncRepo()
      @logger.step __method__.to_s
			performOnRepoInstance(__method__.to_s)
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
				name:     @vars[:build_nmn],
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