module CiCd
	module Builder

		# ---------------------------------------------------------------------------------------------------------------
		def downcaseKey(hash,key)
			hash[key.to_s.downcase.to_sym] = hash[key]
			hash.delete(key)
			hash
		end

		# ---------------------------------------------------------------------------------------------------------------
		def downcaseHashKeys(hash)
			down = {}
			hash.each{|k,v|
				if v.is_a?(Hash)
					v = downcaseHashKeys(v)
				end
				if k.to_s.match(/[A-Z]/)
					k = k.to_s.downcase.to_sym
				end
				down[k] = v
			}
			down
		end

	end
end