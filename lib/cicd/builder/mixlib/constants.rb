module CiCd
	module Builder
		#noinspection RubyStringKeysInHashInspection
		LOGLEVELS = {
			'crit'     => :fatal,
			'critical' => :fatal,
			'err'      => :error,
			'error'    => :error,
			'warn'     => :warn,
			'warning'  => :warn,
			'info'     => :info,
			'debug'    => :debug,
		}

		MYNAME       = File.basename(__FILE__)

	end
end