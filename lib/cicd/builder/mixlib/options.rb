module CiCd
	module Builder

		# ---------------------------------------------------------------------------------------------------------------
		def parseOptions()
			# Parse options
			@options = {
                    log_level:      :warn,
                    #dry_run:       false,

                    gen:            '3.0.0',
                  }.merge @default_options

			opt_parser = OptionParser.new do |opts|
				opts.banner = "Usage: #{MYNAME} [@options]"

				opts.on('-l', '--log_level LEVEL', '--log-level LEVEL', [:trace, :debug, :info, :note, :warn, :error, :fatal, :todo], "Log level ([:trace, :debug, :info, :step, :warn, :error, :fatal, :todo])") do |v|
					@options[:log_level] = v
				end
				opts.on("-f", "--inifile FILE", "INI file with settings") do |v|
					@options[:inifile] = v
				end
				#opts.on("-n", "--[no-]dry-run", "Do a dry run, Default --no-dry-run") do |v|
				#	@options[:dry_run] = v
				#end
			end

			opt_parser.parse!

			# Set up logger
			Logging.init :trace, :debug, :info, :note, :warn, :error, :fatal, :todo
			@logger = Logging.logger(STDOUT,
			                         :pattern      => "%#{::Logging::MAX_LEVEL_LENGTH}l: %m\n",
			                         :date_pattern => '%Y-%m-%d %H:%M:%S')
			@logger.level = @options[:log_level]

			if @options.key?(:inifile)
				@options[:inifile] = File.expand_path(@options[:inifile])
				unless File.exist?(@options[:inifile])
					raise StandardError.new("#{@options[:inifile]} not found!")
				end
				begin
					# ENV.each{ |key,_|
					# 	ENV.delete(key)
					# }
					ini = IniFile.load(@options[:inifile])
					ini['global'].each{ |key,value|
						ENV[key]=value
					}
					def _expand(k,v,regex,rerun)
						matches = v.match(regex)
						if matches
							var = matches[1]
							if ENV.has_key?(var)
								ENV[k]=v.gsub(/\$\{#{var}\}/,ENV[var]).gsub(/\$#{var}/,ENV[var])
							else
								rerun[var] = 1
							end
						end
					end

					pending = nil
					rerun = {}
					begin
						pending = rerun
						rerun = {}
						ENV.to_hash.each{|k,v|
							if v.match(/\$/)
								_expand(k,v,%r'[^\\]\$\{(\w+)\}', rerun)
								_expand(k,v,%r'[^\\]\$(\w+)',     rerun)
							end
						}
						# Should break out the first time that we make no progress!
					end while pending != rerun
				rescue IniFile::Error => e
					# noop
				rescue Exception => e
					@logger.error "#{e.class.name} #{e.message}"
					raise e
				end
			end
			@options
		end

	end
end