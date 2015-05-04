require 'json'

module CiCd
	module Builder

		# ---------------------------------------------------------------------------------------------------------------
		def cleanupBuild()
      @logger.info CLASS+'::'+__method__.to_s
      [ :build_pkg, :build_chk, :build_mdf, :build_mff ].each do |fil|
        if File.exists?(@vars[fil])
          begin
            FileUtils.rm_f(@vars[fil])
          rescue => e
            @logger.error e.to_s
            #raise e
            return Errors::CLEANUPBUILD_EXCEPTION
          end
        end
      end
			if Dir.exists?(@vars[:build_dir])
				begin
					FileUtils.rm_r(@vars[:build_dir])
				rescue => e
					@logger.error e.to_s
					#raise e
					return Errors::CLEANUPBUILD_EXCEPTION
				end
			end
			0
		end

    # ---------------------------------------------------------------------------------------------------------------
    def prepareBuild()
      @logger.step CLASS+'::'+__method__.to_s
      meta = {}
      @vars[:return_code] = 0
      %w[ WORKSPACE PROJECT_NAME ].each do |e|
        unless ENV.has_key?(e)
          puts "#{e} environment variable is required"
          @vars[:return_code] = Errors::MISSING_ENV_VAR
        end
      end
      meta[:Version] = @vars[:version]
      meta[:Release] = @vars[:release]

      if @vars[:return_code] == 0

        if File.exists?(ENV['WORKSPACE']) and (File.directory?(ENV['WORKSPACE']) or File.symlink?(ENV['WORKSPACE']))

          place = ''
          begin
            # Assuming we are in the workspace ...
            place = "Git.open('#{ENV['WORKSPACE']}')"
            req = 'require "git"'
            eval req

            git = Git.open(ENV['WORKSPACE'], :log => @logger)
            place = 'git.log'
            meta[:Commit] = git.log[0].sha
            place = 'git.current_branch'
            meta[:Branch] = git.current_branch
            # meta[:Remotes] = git.remotes

            @vars[:build_ext] = 'tar.gz'
            @vars[:build_bra] = @vars[:branch] || meta[:Branch].gsub(%r([/|]),'.')
            @vars[:build_ver] = "#{meta[:Version]}"
            @vars[:build_rel] = "#{meta[:Release]}"
            @vars[:build_vrb] = "#{@vars[:build_ver]}-release-#{meta[:Release]}-#{@vars[:build_bra]}-#{@vars[:variant]}" #
            @vars[:build_nam] = "#{@vars[:project_name]}-#{@vars[:build_vrb]}"
            @vars[:build_nmn] = "#{@vars[:build_nam]}-build-#{@vars[:build_num]}"
            @vars[:build_dir] = "#{ENV['WORKSPACE']}/#{@vars[:build_nmn]}"
            @vars[:latest_pkg]= "#{@vars[:build_store]}/#{@vars[:build_nmn]}.#{@vars[:build_ext]}"
            @vars[:build_pkg] = "#{@vars[:build_nmn]}.#{@vars[:build_ext]}"
            @vars[:build_chk] = "#{@vars[:build_nmn]}.checksum"
            @vars[:build_mff] = "#{@vars[:build_nmn]}.manifest"
            @vars[:build_mdf] = "#{@vars[:build_nmn]}.meta"
            @vars[:build_mvn] = "#{@vars[:build_ver]}-#{@vars[:build_num]}"
            @vars[:build_mdd] = meta.dup
            #noinspection RubyArgCount
            @vars[:build_mds] = Digest::SHA256.hexdigest(meta.to_s)

            @vars[:return_code] = 0

          rescue Exception => e
            @logger.error "#{e.class}:: '#{place}' - #{e.message}"
            @vars[:return_code] = Errors::PREPAREBUILD_EXCEPTION
          end

        else
          puts "Invalid workspace: '#{ENV['WORKSPACE']}'"
          @vars[:return_code] = Errors::INVALID_WORKSPACE
        end
      end

      if @vars[:return_code] == 0
        @vars[:local_dirs] ||= {}
        %w(artifacts latest).each do |dir|
          @vars[:local_dirs][dir] = "#{ENV['WORKSPACE']}/#{dir}"
          unless File.directory?(dir)
            Dir.mkdir(dir)
          end
        end
      end

      @vars[:return_code]
    end

    # ---------------------------------------------------------------------------------------------------------------
    def makeBuild()
      @logger.step CLASS+'::'+__method__.to_s
      if @vars.has_key?(:build_dir) and @vars.has_key?(:build_pkg)
        begin
          do_build = false
          loadCheckSumFile()
          if 0 == @vars[:return_code]
            do_build = true if @vars[:build_sha].empty?
            do_build = true unless File.exists?(@vars[:build_pkg]) and (Digest::SHA256.file(@vars[:build_pkg]).hexdigest() == @vars[:build_sha])
            if do_build
              @vars[:return_code] = cleanupBuild()
              if 0 == @vars[:return_code]
                @vars[:build_dte] = DateTime.now.strftime('%F %T%:z')
                createMetaData()
                if 0 == @vars[:return_code]
                  @vars[:return_code] = packageBuild()
                  if 0 == @vars[:return_code]
                    @vars[:check_sha] = @vars[:build_sha]
                    @vars[:build_sha] = if File.exists?(@vars[:build_pkg])
                                          Digest::SHA256.file(@vars[:build_pkg]).hexdigest()
                                        else
                                          '0'
                                        end
                    unless IO.write(@vars[:build_chk], @vars[:build_sha]) > 0
                      @logger.error "Unable to store checksum in '#{@vars[:build_chk]}'"
                      @vars[:return_code] = Errors::STORING_BUILD_CHECKSUM
                    end
                  end
                end
              end
            end
          end

          # Report status regardless of return code.
          reportStatus()

          if do_build
            reportResult()
          else
            # Was no need to build :) or a failure :(
            @logger.info "NO_CHANGE: #{ENV['JOB_NAME']} #{ENV['BUILD_NUMBER']} #{@vars[:build_nam]} #{@vars[:build_pkg]} #{@vars[:build_chk]} [#{@vars[:build_sha]}]"
            # @vars[:return_code] = 0
            return 1
          end
        rescue => e
          @logger.error "makeBuild failure: #{e.class.name} #{e.message}"
          @vars[:return_code] = Errors::MAKEBUILD_EXCEPTION
        end
      else
        @logger.error ':build_dir or :build_pkg is unknown'
        @vars[:return_code] = Errors::MAKEBUILD_PREPARATION
      end
      @vars[:return_code]
    end

    # ---------------------------------------------------------------------------------------------------------------
    def loadCheckSumFile
      if File.exists?(@vars[:build_chk])
        @vars[:build_sha] = IO.readlines(@vars[:build_chk])
        unless @vars[:build_sha].is_a?(Array)
          @logger.error "Unable to parse build checksum from #{@vars[:build_chk]}"
          @vars[:return_code] = Errors::PARSING_BUILD_CHECKSUM
        end
        @vars[:build_sha] = @vars[:build_sha][0].chomp()
      else
        @vars[:build_sha] = ''
      end
      @vars[:return_code]
    end

    # ---------------------------------------------------------------------------------------------------------------
    def calcLocalETag(etag, local, size = nil)
      if size == nil
        stat = File.stat(local)
        size = stat.size
      end
      @logger.debug "Calculate etag to match #{etag}"
      match = etag.match(%r'-(\d+)$')
      check = if match
                require 's3etag'
                parts = match[1].to_i
                chunk = size.to_f / parts.to_f
                mbs = (chunk.to_f / 1024 /1024 + 0.5).to_i
                part_size = mbs * 1024 * 1024
                chkit = S3Etag.calc(file: local, threshold: part_size, min_part_size: part_size, max_parts: parts)
                @logger.debug "S3Etag Calculated #{chkit} : (#{size} / #{part_size}) <= #{parts}"
                chunks = size / part_size
                while chkit != etag and chunks <= parts and chunks > 0 and (size > part_size)
                  # Go one larger if a modulus remains and we have the right number of parts
                  mbs += 1
                  part_size = mbs * 1024 * 1024
                  chunks = size.to_f / part_size
                  chkit = S3Etag.calc(file: local, threshold: part_size, min_part_size: part_size, max_parts: parts)
                  @logger.debug "S3Etag Calculated #{chkit} : (#{size} / #{part_size}) <= #{parts}"
                end
                @logger.warn "Unable to match etag #{etag}!" if chkit != etag
                chkit
              else
                Digest::MD5.file(local).hexdigest
              end
    end

    # ---------------------------------------------------------------------------------------------------------------
		def packageBuild()
      @logger.info CLASS+'::'+__method__.to_s
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
		def cleanupAfterUpload()
      @logger.info CLASS+'::'+__method__.to_s
			@logger.debug = %(Prior to VERSION 0.9.58 there was no #{__method__.to_s} action)
		end

    # ---------------------------------------------------------------------------------------------------------------
    def createMetaData()
      @logger.info CLASS+'::'+__method__.to_s
      @vars[:build_mdd].merge!({
                                :Generation => @options[:gen],
                                :Project => @vars[:project_name],
                                :Variant => @vars[:variant],
                                :Build => @vars[:build_num],
                                :Date => @vars[:build_dte],
                                :Builder => VERSION,

                                      })
      json = JSON.pretty_generate( @vars[:build_mdd], { indent: "\t", space: ' '})
      unless IO.write(@vars[:build_mdf], json) > 0
        @logger.error "Unable to store metadata in '#{@vars[:build_mdf]}'"
        @vars[:return_code] = Errors::STORING_BUILD_METADATA
      end
      @vars[:return_code]
    end

  end
end