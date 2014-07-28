module CiCd
	module Builder
		module Errors

			class Unknown < StandardError ; end
			class Internal < Unknown ; end
			class InvalidVersion < Unknown ; end
			class InvalidVersionConstraint < Unknown ; end

		end
	end
end