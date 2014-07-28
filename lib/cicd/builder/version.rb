module CiCd
	# noinspection ALL
  module Builder
		# file    = File.expand_path("#{File.dirname(__FILE__)}/../../../VERSION")
		# lines   = File.readlines(file)
		# version = lines[0]
		version = '0.9.18'
		VERSION = version unless const_defined?('VERSION')
		major, minor, tiny = VERSION.split('.')
		MAJOR   = major unless const_defined?('MAJOR')
    MINOR   = minor unless const_defined?('MINOR')
    TINY    = tiny unless const_defined?('TINY')
		PATCH   = TINY unless const_defined?('PATCH')
	end
end
