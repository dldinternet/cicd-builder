require 'cicd/builder/version'
module CiCd
	module Builder

    ENV_IGNORED = %w(LS_COLORS AWS_ACCESS_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SECRET_KEY)

		require 'awesome_print'
		require 'optparse'
		require 'inifile'
		require 'logging'
		require 'net/http'
		require 'uri'
		require 'fileutils'
		require 'digest'
		require 'yajl/json_gem'
		require 'aws-sdk-core'
		require 'aws-sdk-resources'

		_lib=File.dirname(__FILE__)
		$:.unshift(_lib) unless $:.include?(_lib)

		require 'cicd/builder/version'
		require 'cicd/builder/mixlib/constants'

		#noinspection ALL
		class BuilderBase
			attr_accessor :default_options
			attr_accessor :options
			attr_accessor :logger
			attr_accessor :vars

			def initialize()
        @vars = {
            return_code: -1
        }
				@default_options = {
						builder:        ::CiCd::Builder::VERSION,
						env_keys:       %w(JENKINS_HOME BUILD_NUMBER JOB_NAME)
				}
			end

			require 'cicd/builder/mixlib/errors'
			require 'cicd/builder/mixlib/utils'
			require 'cicd/builder/mixlib/options'
			require 'cicd/builder/mixlib/environment'
			require 'cicd/builder/mixlib/repo'
			require 'cicd/builder/mixlib/build'

			# ---------------------------------------------------------------------------------------------------------------
      def getBuilderVersion
        {
            version:  VERSION,
            major:    MAJOR,
            minor:    MINOR,
            patch:    PATCH,
        }
      end

			# ---------------------------------------------------------------------------------------------------------------
			def setup()
				$stdout.write("CiCd::Builder v#{VERSION}\n")
        @default_options[:env_keys] = Hash[@default_options[:env_keys].flatten.map.with_index.to_a].keys
				parseOptions()
			end

			# ---------------------------------------------------------------------------------------------------------------
			def run()
				setup()

        ret = 0
				%w(checkEnvironment getVars).each do |step|
          @logger.step "#{step}"
          ret = send(step)
          break unless ret == 0
				end
				if ret == 0
					@vars[:actions].each do |step|
						@logger.step "#{step}"
						ret = send(step)
						break unless ret == 0
					end
				end

				@vars[:return_code]
			end

		end

    def isSameDirectory(pwd, workspace)
      pwd = File.realdirpath(File.expand_path(pwd))
      workspace = File.realdirpath(File.expand_path(workspace))
      unless pwd == workspace

      end
      return pwd, workspace
    end

	end
end