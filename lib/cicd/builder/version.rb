module CiCd
	# noinspection ALL
  module Builder
		# file    = File.expand_path("#{File.dirname(__FILE__)}/../../../VERSION")
		# lines   = File.readlines(file)
		# version = lines[0]
		version = '0.9.10'
		VERSION = version
		MAJOR, MINOR, TINY = VERSION.split('.')
		PATCH = TINY
	end
end
