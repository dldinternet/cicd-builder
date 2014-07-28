require 'json'

module CiCd
	module Builder

		# ---------------------------------------------------------------------------------------------------------------
		def cleanupBuild()
      [ :build_pkg, :build_chk, :build_mdf, :build_mff ].each do |fil|
        if File.exists?(@vars[fil])
          begin
            FileUtils.rm_f(@vars[fil])
          rescue => e
            @logger.error e.to_s
            #raise e
            return -96
          end
        end
      end
			if Dir.exists?(@vars[:build_dir])
				begin
					FileUtils.rm_r(@vars[:build_dir])
				rescue => e
					@logger.error e.to_s
					#raise e
					return -95
				end
			end
			0
		end

    # ---------------------------------------------------------------------------------------------------------------
    def prepareBuild()
      meta = {}
      %w[ WORKSPACE PROJECT_NAME VERSION RELEASE ].each do |e|
        unless ENV.has_key?(e)
          raise "#{e} environment variable is required"
        end
      end
      meta[:Version] = ENV['VERSION']
      meta[:Release] = ENV['RELEASE']

      place = ''
      begin
        place = 'require "git"'
        eval place

        # Assuming we are in the workspace ...
        place = "Git.open('#{ENV['WORKSPACE']}')"
        git = Git.open(ENV['WORKSPACE'], :log => @logger)
        place = 'git.log'
        meta[:Commit] = git.log[0].sha
        place = 'git.current_branch'
        meta[:Branch] = git.current_branch

        @vars[:build_bra] = meta[:Branch].gsub(%r([/|]),'.')
        @vars[:build_ver] = "#{meta[:Version]}"
        @vars[:build_vrb] = "#{@vars[:build_ver]}-release-#{meta[:Release]}-#{@vars[:build_bra]}-#{@vars[:variant]}" #
        @vars[:build_nam] = "#{@vars[:project_name]}-#{@vars[:build_vrb]}"
        @vars[:build_rel] = "#{@vars[:build_nam]}-build-#{@vars[:build_num]}"
        @vars[:build_dir] = "#{ENV['WORKSPACE']}/#{@vars[:build_rel]}"
        @vars[:latest_pkg]= "#{@vars[:build_store]}/#{@vars[:build_rel]}.tar.gz"
        @vars[:build_pkg] = "#{@vars[:build_rel]}.tar.gz"
        @vars[:build_chk] = "#{@vars[:build_rel]}.checksum"
        @vars[:build_mff] = "#{@vars[:build_rel]}.manifest"
        @vars[:build_mdf] = "#{@vars[:build_rel]}.meta"
        @vars[:build_mdd] = meta.dup
        #noinspection RubyArgCount
        @vars[:build_mds] = Digest::SHA256.hexdigest(meta.to_s)

        @vars[:return_code] = 0

      rescue Exception => e
        @logger.error "#{e.class}:: '#{place}' - #{e.message}"
        @vars[:return_code] = -98
      end

      @vars[:return_code]
    end

    # ---------------------------------------------------------------------------------------------------------------
    def makeBuild()
      if @vars.has_key?(:build_dir) and @vars.has_key?(:build_pkg)
        begin
          do_build = false
          if File.exists?(@vars[:build_chk])
            @vars[:build_sha] = IO.readlines(@vars[:build_chk])
            unless @vars[:build_sha].is_a?(Array)
              @logger.error "Unable to parse build checksum from #{@vars[:build_chk]}"
              return -97
            end
            @vars[:build_sha] = @vars[:build_sha][0].chomp()
          else
            @vars[:build_sha] = ''
            do_build = true
          end
          unless File.exists?(@vars[:build_pkg])
            do_build = true
          end
          if do_build
            @vars[:return_code] = cleanupBuild()
            return @vars[:return_code] unless @vars[:return_code] == 0
            @vars[:build_dte] = DateTime.now.strftime("%F %T%:z")
            createMetaData()
            @vars[:return_code] = packageBuild()
            if 0 == @vars[:return_code]
              @vars[:check_sha] = @vars[:build_sha]
              @vars[:build_sha] = Digest::SHA256.file(@vars[:build_pkg]).hexdigest()
              IO.write(@vars[:build_chk], @vars[:build_sha])
            end
            reportStatus()
            reportResult()
          else
            reportStatus()

            # No need to build again :)
            @logger.info "NO_CHANGE: #{ENV['JOB_NAME']} #{ENV['BUILD_NUMBER']} #{@vars[:build_nam]} #{@vars[:build_pkg]} #{@vars[:build_chk]} [#{@vars[:build_sha]}]"
            @vars[:return_code] = 0
            return 1
          end
        rescue => e
          @logger.error "#{e.class.name} #{e.message}"
          @vars[:return_code] = -99
        end
      else
        @logger.error ":build_dir or :build_pkg is unknown"
        @vars[:return_code] = 2
      end
      @vars[:return_code]
    end

    # ---------------------------------------------------------------------------------------------------------------
		def packageBuild()
			excludes=%w(*.iml *.txt *.sh *.md .gitignore .editorconfig .jshintrc *.deprecated adminer doc)
			excludes = excludes.map{ |e| "--exclude=#{@vars[:build_nam]}/#{e}" }.join(' ')
			cmd = %(cd #{ENV['WORKSPACE']}; tar zcvf #{@vars[:build_pkg]} #{excludes} #{@vars[:build_nam]} 1>#{@vars[:build_pkg]}.manifest)
			@logger.info cmd
			logger_info = %x(#{cmd})
			ret = $?.exitstatus
			@logger.info logger_info
			FileUtils.rmtree(@vars[:build_dir])
			ret
		end

    # ---------------------------------------------------------------------------------------------------------------
    def createMetaData()
      @vars[:build_mdd].merge!({
                                :Generation => @options[:gen],
                                :Project => @vars[:project_name],
                                :Variant => @vars[:variant],
                                :Build => @vars[:build_num],
                                :Date => @vars[:build_dte],
                                :Builder => VERSION,

                                      })
      json = JSON.pretty_generate( @vars[:build_mdd], { indent: "\t", space: ' '})
      IO.write(@vars[:build_mdf], json)
    end

  end
end