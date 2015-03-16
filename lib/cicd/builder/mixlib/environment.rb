module CiCd
	module Builder
    require 'awesome_print'

		# ---------------------------------------------------------------------------------------------------------------
		def checkEnvironment()
      @logger.info __method__.to_s
			# [2013-12-30 Christo] Detect CI ...
			unless ENV.has_key?('JENKINS_HOME')
				@logger.error "Sorry, your CI environment is not supported at this time (2013-12-30) ... Christo De Lange\n"+
				'This script is developed for Jenkins so either you are not using Jenkins or you ran me outside of the CI ecosystem ...'
				return 99
			end

			# Check for the necessary environment variables
			map_keys = {}

			@options[:env_keys].each { |k|
				map_keys[k]= (not ENV.has_key?(k) or ENV[k].empty?)
			}
			missing = map_keys.keys.select{ |k| map_keys[k] }

			if missing.count() > 0
				# ap missing
				#raise Exception.new("Need these environment variables: #{missing}")
				puts("Need these environment variables: #{missing.ai}")
        return 1
			end
			0
		end

		# ---------------------------------------------------------------------------------------------------------------
		def getVars()
      @logger.info __method__.to_s
			@vars               ||= {}
			@vars[:release]     = 'latest'
			@vars[:build_store] = '/tmp'
			@vars[:variant]     = 'SNAPSHOT'

			if ENV.has_key?('PROJECT_NAME')
				@vars[:project_name] = ENV['PROJECT_NAME']
			end

			if ENV.has_key?('RELEASE')
				@vars[:release] = ENV['RELEASE']
      elsif File.exists?((version_file=File.join(ENV['REPO_DIR'], 'RELEASE')))
        lines = File.readlines(version_file)
        @vars[:release] = lines.shift.chomp() if lines.count > 0
      else
        raise "'RELEASE' was not provided in either environment or #{version_file} file"
			end

			if ENV.has_key?('VERSION')
				@vars[:version] = ENV['VERSION']
      elsif File.exists?((version_file=File.join(ENV['REPO_DIR'], 'VERSION')))
        lines = File.readlines(version_file)
        @vars[:version] = lines.shift.chomp() if lines.count > 0
      else
        raise "'VERSION' was not provided in either environment or #{version_file} file"
			end

			if ENV.has_key?('BUILD_STORE')
				@vars[:build_store] = "#{ENV['BUILD_STORE']}"
			end

			if ENV.has_key?('VARIANT')
				@vars[:variant] = "#{ENV['VARIANT']}"
      end

			if ENV.has_key?('BUILD_NUMBER')
				@vars[:build_num] = "#{ENV['BUILD_NUMBER']}"
			end

			@vars[:return_code] = getLatest()
		end

    # ---------------------------------------------------------------------------------------------------------------
    def getLatest
      ret = 0
      @vars[:vars_fil] = "#{@vars[:build_store]}/#{ENV['JOB_NAME']}-#{@vars[:variant]}.env"
      @vars[:latest_fil] = "#{@vars[:build_store]}/#{ENV['JOB_NAME']}-#{@vars[:variant]}.latest"
      @vars[:latest_ver] = ''
      @vars[:latest_sha] = ''
      @vars[:latest_pkg] = ''
      @vars[:latest_ext] = @vars[:build_ext]
      if @vars[:build_nam]
        @vars[:latest_pkg] = "#{@vars[:build_store]}/#{@vars[:build_nam]}.#{@vars[:latest_ext]}"
        unless File.exists?(@vars[:latest_pkg])
          if File.exists?("#{@vars[:build_store]}/#{@vars[:build_nam]}.tar.gz")
            @vars[:latest_ext] = 'tar.gz'
            @vars[:latest_pkg] = "#{@vars[:build_store]}/#{@vars[:build_nam]}.#{@vars[:latest_ext]}"
          end
        end
      end
      ret = loadLatestVarsFile
      ret
    end

    # ---------------------------------------------------------------------------------------------------------------
    def loadLatestVarsFile
      ret = 0
      if File.exists?(@vars[:latest_fil])
        @vars[:latest_ver] = IO.readlines(@vars[:latest_fil])
        unless @vars[:latest_ver].is_a?(Array)
          @logger.error "Unable to parse latest version from #{@vars[:latest_fil]}"
          ret = Errors::PARSING_LATEST_VERSION
        end
        @vars[:latest_sha] = @vars[:latest_ver][1].chomp() if (@vars[:latest_ver].length > 1)
        @vars[:latest_ver] = @vars[:latest_ver][0].chomp()
        if @vars[:latest_ver] =~ %r'-\d+$'
          @vars[:latest_ver], @vars[:latest_rel] = @vars[:latest_ver].split(/-/)
        end
      end
      ret
    end

    # ---------------------------------------------------------------------------------------------------------------
    def saveLatestVarsFile
      @logger.info "Save latest build info to #{@vars[:latest_fil]}"
      wrote = IO.write(@vars[:latest_fil], "#{@vars[:build_ver]}-#{@vars[:build_rel]}\n#{@vars[:build_sha]}")
      ret = (wrote > 0) ? 0 : Errors::SAVE_LATEST_VARS
    end

    # ---------------------------------------------------------------------------------------------------------------
		def saveEnvironment(ignored=ENV_IGNORED)
      @logger.step __method__.to_s
			@logger.info "Save environment to #{@vars[:vars_fil]}"
			vstr = ['[global]']
			ENV.to_hash.sort.each{|k,v|
				vstr << %(#{k}="#{v}") unless ignored.include?(k)
			}

      @vars[:return_code] = (IO.write(@vars[:vars_fil], vstr.join("\n")) > 0) ? 0 : Errors::SAVE_ENVIRONMENT_VARS
      return @vars[:return_code]
		end

    # ---------------------------------------------------------------------------------------------------------------
    def saveBuild()
      @logger.info __method__.to_s
      begin
        raise 'ERROR: Checksum not read'       unless @vars.has_key?(:latest_sha)
        raise 'ERROR: Checksum not calculated' unless @vars.has_key?(:build_sha)
        change = false
        if @vars[:latest_sha] != @vars[:build_sha]
          change = true
          @logger.info "CHANGE: Checksum [#{@vars[:latest_sha]}] => [#{@vars[:build_sha]}]"
        end
        if @vars[:latest_ver] != @vars[:build_ver]
          change = true
          @logger.info "CHANGE: Version [#{@vars[:latest_ver]}] => [#{@vars[:build_ver]}]"
        end
        if @vars[:latest_rel] != @vars[:build_rel]
          change = true
          @logger.info "CHANGE: Release [#{@vars[:latest_rel]}] => [#{@vars[:build_rel]}]"
        end
        unless File.file?(@vars[:build_pkg])
          change = true
          @logger.info "CHANGE: No #{@vars[:build_pkg]}"
        end
        unless File.symlink?(@vars[:latest_pkg])
          change = true
          @logger.info "CHANGE: No #{@vars[:latest_pkg]}"
        end

        if change
          if @vars[:latest_pkg] != @vars[:build_pkg] and  File.file?(@vars[:build_pkg])
            @logger.info "Link #{@vars[:latest_pkg]} to #{@vars[:build_pkg]}"
            begin
              File.unlink(@vars[:latest_pkg])
            rescue
              # noop
            end
            File.symlink(@vars[:build_pkg], @vars[:latest_pkg])
          else
            @logger.warn "Skipping link #{@vars[:latest_pkg]} to missing '#{@vars[:build_pkg]}'"
          end
          @vars[:return_code] = saveLatestVarsFile()
          unless 0 == @vars[:return_code]
            @logger.error "Failed to save latest vars file: #{@vars[:latest_fil]}"
            return @vars[:return_code]
          end
          @vars[:return_code] = saveEnvironment(ENV_IGNORED)
          unless 0 == @vars[:return_code]
            @logger.error "Failed to save environment vars file: #{@vars[:vars_fil]}"
            return @vars[:return_code]
          end
          # NOTE the '.note'!
          @logger.note "CHANGE: #{ENV['JOB_NAME']} (#{@vars[:build_ver]}-#{@vars[:build_rel]}[#{@vars[:build_sha]}])"
        else
          @logger.info "Artifact #{@vars[:latest_pkg]} unchanged (#{@vars[:latest_ver]}-#{@vars[:latest_rel]} [#{@vars[:latest_sha]}])"
          @logger.note "NO_CHANGE: #{ENV['JOB_NAME']} #{@vars[:latest_ver]}"
        end
        @vars[:return_code] = 0
      rescue => e
        @logger.error "#{e.backtrace[0]}: #{e.class.name} #{e.message}"
        @vars[:return_code] = 2
      end
      @vars[:return_code]
    end

    def reportResult()
      if 0 == @vars[:return_code]
        # NOTE the '.note'!
        @logger.note  "CHANGE:  #{ENV['JOB_NAME']} #{ENV['BUILD_NUMBER']} #{@vars[:build_nam]} (#{@vars[:build_pkg]}) [#{@vars[:check_sha]}] => [#{@vars[:build_sha]}]"
      else
        @logger.error "FAILURE: #{ENV['JOB_NAME']} #{ENV['BUILD_NUMBER']} #{@vars[:build_pkg]} #{@vars[:return_code]}"
      end
    end

		# ---------------------------------------------------------------------------------------------------------------
		def reportStatus(ignored=ENV_IGNORED)
      # [2013-12-30 Christo] Report status,environment, etc.

			if @logger.level < ::Logging::LEVELS['warn']
				@logger.info '='*100
				@logger.info Dir.getwd()
				@logger.info '='*100

				@logger.info "Config:"
				@options.each{|k,v|
					unless ignored.include?(k)
						@logger.info sprintf("%25s: %s", "#{k.to_s}",  "#{v.to_s}")
					end
				}

				@logger.info '='*100

				@logger.info "Parameters:"
				@vars.sort.each{|k,v|
					unless ignored.include?(k)
						@logger.info sprintf("%25s: %s", "#{k.to_s}",  "#{v.to_s}")
					end
				}

				@logger.info '='*100
			end

			if @logger.level < ::Logging::LEVELS['info']
				@logger.debug '='*100
				@logger.debug "Environment:"
				ENV.sort.each{|k,v|
					unless ignored.include?(k)
						@logger.debug sprintf("%25s: %s", "#{k.to_s}",  "#{v.to_s}")
					end
				}

				@logger.debug '='*100
			end
		end

	end
end