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

    # ---------------------------------------------------------------------------------------------------------------
    def addArtifact(artifacts, script, prefix, opts = {})
      key = "#{@vars[:project_name]}/#{@vars[:variant]}/#{@vars[:build_nam]}/#{script.gsub(%r|^#{prefix}|, '')}"
      # Store the artifact - be sure to inherit possible overrides in pkg name and ext but dictate the drawer!
      artifacts << {
          key: key,
          data: {:file => script}.merge(opts),
      }
    end

  end
end