require 'cicd/builder/version'
module CiCd
	module Builder

		require 'awesome_print'
		require 'optparse'
		require 'inifile'
		require 'logging'
		require 'net/http'
		require 'uri'
		require 'fileutils'
		require 'digest'
		require 'yajl/json_gem'
		require 'aws-sdk'

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
			def run()
				$stdout.write("CiCd::Builder v#{@VERSION}\n")
				parseOptions()

				ret = checkEnvironment()
				if 0 == ret
					ret = getVars()
          if 0 == ret
            ret = prepareBuild()
            if 0 == ret
              ret = makeBuild()
              if 0 == ret
                ret = saveBuild()
                if 0 == ret
                  ret = uploadBuildArtifacts()
                  if 0 == ret
                    # noop
                  end
                end
              end
            end
          end
        end

				@vars[:return_code]
			end

		end

	end
end