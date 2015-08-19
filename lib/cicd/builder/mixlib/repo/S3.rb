require 'aws-sdk-core'
require 'aws-sdk-resources'

module CiCd
	module Builder
    module Repo
      class S3 < CiCd::Builder::Repo::Base

        # ---------------------------------------------------------------------------------------------------------------
        def initialize(builder)
          raise "Missing variable AWS_S3_BUCKET" unless ENV.has_key?('AWS_S3_BUCKET')
          super(builder)
        end

        # ---------------------------------------------------------------------------------------------------------------
        def getS3()
          region = ENV['AWS_REGION'] || ::Aws.config[:region] || 'us-east-1'
          unless @s3
            # noinspection RubyArgCount
            @s3 = ::Aws::S3::Client.new(region: region)
          end
          unless @s3 and ((@s3.config.access_key_id and @s3.config.secret_access_key) or @s3.config.credentials)
            @logger.warn "Unable to find AWS credentials in standard locations:
ENV['AWS_ACCESS_KEY'] and ENV['AWS_SECRET_ACCESS_KEY']
Aws.config[:credentials]
Shared credentials file, ~/.aws/credentials
EC2 Instance profile
"
            if ENV['AWS_PROFILE']
              @logger.info "Trying profile '#{ENV['AWS_PROFILE']}' explicitly"
              creds = Aws::SharedCredentials.new( path: File.expand_path('~/.aws/credentials'), profile: ENV['AWS_PROFILE'] )
              if creds.loadable?
                # noinspection RubyArgCount
                @s3 = ::Aws::S3::Client.new(region: region, credentials: creds)
              end
            else
              @logger.warn 'No AWS_PROFILE defined'
            end
          end
          unless @s3 and ((@s3.config.access_key_id and @s3.config.secret_access_key) or @s3.config.credentials)
            raise 'Unable to find AWS credentials!'
          end
          @s3
        end

        # ---------------------------------------------------------------------------------------------------------------
        def uploadToRepo(artifacts)
          @logger.info CLASS+'::'+__method__.to_s
          s3 = getS3()
          artifacts.each{|art|

            s3_obj = maybeS3Object(art[:key], s3)
            upload = false
            if art[:data][:data]
              # md5 = Digest::MD5.hexdigest(art[:data][:data])
              tempArtifactFile('artifact', art[:data])
            end
            if s3_obj.nil?
              upload = true
              etag   = ''
            else
              @logger.info "s3://#{ENV['AWS_S3_BUCKET']}/#{art[:key]} exists"
              etag = s3_obj.etag.gsub(/"/, '')
            end
            md5 = if art[:data].has_key?(:file)
                    # md5 = Digest::MD5.file(art[:data][:file]).hexdigest
                    calcLocalETag(etag, art[:data][:file])
                  else
                    raise "Internal error: No :file in #{art[:data].ai}"
                  end
            unless s3_obj.nil?
              unless etag == md5
                checksum = s3_obj.metadata[:checksum]
                unless checksum and checksum == md5
                  @logger.warn "s3://#{ENV['AWS_S3_BUCKET']}/#{art[:key]} is different from our #{art[:key]}(#{s3_obj.etag} <=> #{md5})"
                  upload = true
                end
              end
            end

            if upload
              @logger.info "Upload new s3://#{ENV['AWS_S3_BUCKET']}/#{art[:key]}"
              # Get size before upload changes our object
              body = nil
              if art[:data].has_key?(:file)
                size = File.size(art[:data][:file])
                body = File.open(art[:data][:file], 'r')
              else
                # size = art[:data][:data].length
                # body = art[:data][:data]
                raise "Internal error: No :file in #{art[:data].ai}"
              end
              art[:data][:metadata] = {checksum: md5, digest: "md5=#{md5}"}
              # art[:data][:'x-amz-meta-digest'] = "md5=#{md5}"
              res = s3.put_object(        bucket: ENV['AWS_S3_BUCKET'],
                                             key: art[:key],
                                            body: body,
                                           # acl: 'authenticated-read',
                                  content_length: size,
                                        metadata: art[:data][:metadata],
                                  )
              s3_obj = maybeS3Object(art[:key], s3)
              raise "Failed to upload '#{art[:key]}'" unless s3_obj
              if art.has_key?(:public_url)
                @vars[art[:public_url]] = s3_obj.public_url
              end
              if art.has_key?(:read_url)
                @vars[art[:read_url]]   = s3_obj.presigned_url(:get, expires_in: 86400)
                @logger.info "#{art[:label]}: #{@vars[art[:read_url]]}"
              end
            end
            if art[:data][:temp]
              File.unlink(art[:data][:file])
            end
          }
          0
        end

        def maybeS3Object(key, s3 = nil)
          s3 ||= getS3()
          s3_obj = begin
            obj = ::Aws::S3::Object.new(bucket_name: ENV['AWS_S3_BUCKET'], key: key, client: s3)
            obj.etag
            obj
          rescue Aws::S3::Errors::NotFound
            nil
          rescue Aws::S3::Errors::NoSuchKey
            nil
          rescue Aws::S3::Errors::Forbidden
            nil
          rescue Exception => e
            nil
          end
          # noinspection RubyUnnecessaryReturnValue
          s3_obj
        end

        # ---------------------------------------------------------------------------------------------------------------
        def _update(hash, key, value)
          h = {}
          i = -1
          hash[key].each { |v| h[v] = i+=1 }
          unless h.has_key?(value)
            h[value] = h.keys.size # No -1 because this is evaluated BEFORE we make the addition!
          end
          s = h.sort_by { |_, v| v }
          s = s.map { |v| v[0] }
          hash[key] = s
          h[value]
        end

        # ---------------------------------------------------------------------------------------------------------------
        def takeInventory()
          @logger.info CLASS+'::'+__method__.to_s
          varianth  = nil
          # Read and parse in JSON
          key, json, over = pullInventory()
          unless json.nil?
            if json['container'] and json['container']['variants']
              # but does not have our variant then add it
              variants = json['container']['variants']
              unless variants[@vars[:variant]]
                variants[@vars[:variant]] = {}
                varianth = variants[@vars[:variant]]
                varianth['builds'] = []
                varianth['branches'] = []
                varianth['versions'] = []
                varianth['releases'] = []
                varianth['latest'] = {
                    branch: -1,
                    version: -1,
                    build: -1,
                    release: -1,
                }
              end
              varianth = variants[@vars[:variant]]
              # If the inventory 'latest' format is up to date ...
              unless varianth['latest'] and
                  varianth['latest'].is_a?(Hash)
                # Start over ... too old/ incompatible
                over = true
              end
            else
              # Start over ... too old/ incompatible
              over = true
            end
          end
          # Starting fresh ?
          if over or json.nil?
            json_s = initInventory()
          else
            raise CiCd::Builder::Errors::Internal.new sprintf('Internal logic error! %s::%d', __FILE__,__LINE__) if varianth.nil?
            # Add the new build if we don't have it
            unless varianth['builds'].map { |b| b['build_name'] }.include?(@vars[:build_nmn])
              # noinspection RubyStringKeysInHashInspection
              filing = _createFiling(json, {
                                             'drawer'        => (@vars[:build_mvn] ? "#{@vars[:build_nam]}/#{@vars[:build_mvn]}" : @vars[:build_nam]),
                                             'build_name'    => @vars[:build_nmn],
                                             'build_number'  => @vars[:build_num],
                                             'release'       => @vars[:release],
                                             'artifacts'     => @vars[:artifacts],
                                             'build_ext'     => @vars[:build_ext],
                                         } )
              varianth['builds'] << filing
            end
            build_lst = (varianth['builds'].size-1)
            build_rel = _getLatestRelease(build_lst, varianth)

            # Add new branch ...
            build_bra = _update(varianth, 'branches', @vars[:build_bra])
            # Add new version ...
            build_ver = _update(varianth, 'versions', @vars[:build_ver])

            # Set latest
            varianth['latest'] = {
                branch:  build_bra,
                version: build_ver,
                build:   build_lst,
                release: build_rel,
            }
            json['gen'] = @options[:gen]
            json_s = JSON.pretty_generate( json, { indent: "\t", space: ' '})
          end
          pushInventory(json_s, key)
        end

        # ---------------------------------------------------------------------------------------------------------------
        # noinspection RubyStringKeysInHashInspection
        def _createFiling(json, args)
          filing = {
              'drawer'        => args['drawer'],
              'build_name'    => args['build_name'],
              'build_number'  => args['build_number'],
              'release'       => args['release'],
          }
          if args['artifacts']
            # filing['artifacts'] = args['artifacts'].map { |artifact| File.basename(artifact[:key]) }
            filing['artifacts'] = args['artifacts'].map { |artifact| artifact[:key].gsub(%r|^.*#{args['drawer']}/|, '') }
          end
          assembly = json['container']['assembly'] or raise("Expected an 'assembly'")
          if assembly['extension'] != args['build_ext']
            filing['assembly'] = {
                'extension' => args['build_ext'],
                'type'      => 'tarbzip2'
            }
          end
          filing
        end

        def pushInventory(json_s, key)
          @logger.info CLASS+'::'+__method__.to_s
          begin
            md5 = Digest::MD5.hexdigest(json_s)
            # [:'x-amz-meta-digest'] = "md5=#{md5}"
            resp = getS3.put_object(bucket: ENV['AWS_S3_BUCKET'],
                                    key: key,
                                    body: json_s,
                                    # acl: 'authenticated-read',
                                    metadata: {checksum: md5, digest: "md5=#{md5}"},
            )
            s3_obj = maybeS3Object(key)
            # s3_obj.etag
            @logger.info "Inventory URL: #{s3_obj.presigned_url(:get, expires_in: 86400)}"
            return 0
          rescue Exception => e
            @logger.error("Exception: #{e.class.name}: #{e.message}\n#{e.backtrace.ai}")
            return Errors::INVENTORY_UPLOAD_EXCEPTION
          end
        end

        # ---------------------------------------------------------------------------------------------------------------
        def _getLatestRelease(build_lst, varianth)
          build_rel = build_lst
          i = -1
          varianth['builds'].each { |h|
            i += 1
            convert_build(h)
            convert_build(varianth['builds'][build_rel])
            if h['release'].to_f > varianth['builds'][build_rel]['release'].to_f
              build_rel = i
            elsif h['release'] == varianth['builds'][build_rel]['release']
              build_rel = i if h['build_number'].to_i > varianth['builds'][build_rel]['build_number'].to_i
            end
          }
          build_rel
        end

        # ---------------------------------------------------------------------------------------------------------------
        def _getLatestBranch(build_lst, varianth)
          # noinspection RubyHashKeysTypesInspection
          map = Hash[varianth['branches'].map.with_index.to_a]
          build_bra = (varianth['builds'].size > 0) ? map[_getBranch(@vars, varianth['builds'][build_lst])] : -1

          i = -1
          varianth['builds'].each { |h|
            i += 1
            convert_build(h)
            brah = _getBranch(@vars, h)
            bral = _getBranch(@vars, varianth['builds'][build_bra])
            if map[brah] > map[bral]
              build_bra = map[brah]
            end
          }
          build_bra
        end

        # ---------------------------------------------------------------------------------------------------------------
        def _getLatestVersion(build_lst, varianth)
          # noinspection RubyHashKeysTypesInspection
          map = Hash[varianth['versions'].map.with_index.to_a]
          if varianth['builds'].size > 0
            build_ver = map[_getVersion(@vars, varianth['builds'][build_lst])]
            verl = _getVersion(@vars, varianth['builds'][build_ver])
          else
            build_ver = -1
            verl = '0.0.0'
          end

          gt   = ::Semverse::Constraint.new "> #{verl}"
          eq   = ::Semverse::Constraint.new "= #{verl}"

          i = -1
          varianth['builds'].each { |h|
            i += 1
            convert_build(h)
            verh = _getVersion(@vars, h)
            version = ::Semverse::Version.new(verh)
            if gt.satisfies?(version)
              build_ver = map[verh]
              build_lst = i
              gt = ::Semverse::Constraint.new "> #{verh}"
              eq = ::Semverse::Constraint.new "= #{verh}"
            elsif eq.satisfies?(version)
              if h['build_number'].to_i > varianth['builds'][build_lst]['build_number'].to_i
                build_ver = map[verh]
                build_lst = i
                gt = ::Semverse::Constraint.new "> #{verh}"
                eq = ::Semverse::Constraint.new "= #{verh}"
              end
            end
          }
          build_ver
        end

        # ---------------------------------------------------------------------------------------------------------------
        def pullInventory(product=nil)
          json = nil
          key, s3_obj = checkForInventory(product)
          # If the inventory has started then add to it else create a new one
          if s3_obj.nil?
            # Start a new inventory
            over = true
          else
            resp = s3_obj.get()
            body = resp.body
            if body.is_a?(String)
              json_s = resp.data
            else
              body.rewind
              json_s = body.read()
            end
            json = Yajl::Parser.parse(json_s)
            over = false
            # Is the inventory format up to date ...
            constraint = ::Semverse::Constraint.new "<= #{@options[:gen]}"
            version = ::Semverse::Version.new(json['gen'])
            # raise CiCd::Builder::Errors::InvalidVersion.new "The constraint failed: #{json['gen']} #{constraint}"

            unless constraint.satisfies?(version)
              raise CiCd::Builder::Errors::InvalidVersion.new "The inventory generation is newer than I can manage: #{version} <=> #{@options[:gen]}"
            end
          end
          return key, json, over
        end

        # ---------------------------------------------------------------------------------------------------------------
        def checkForInventory(product=nil)
          if product.nil?
            product = @vars[:project_name]
          end
          key = "#{product}/INVENTORY.json"
          s3_obj = maybeS3Object(key)
          return key, s3_obj
        end

        # ---------------------------------------------------------------------------------------------------------------
        def convert_build(h)
          if h.has_key?('number')
            h['build_number'] = h['number']
            h.delete 'number'
          elsif h.has_key?('build_number')
            h.delete 'number'
          else
            h_build  = h.has_key?('build') ? h['build'] : h['build_name']
            h_number = h_build.gsub(/^.*?-build-([0-9]+)$/, '\1').to_i

            h['build_number'] = h_number
            h['build_name']   = h_build
            h.delete 'build'
            h.delete 'number'
          end
          if h.has_key?('build')
            h_build  = h.has_key?('build')
            h_number = h_build.gsub(/^.*?-build-([0-9]+)$/, '\1').to_i

            h['build_number'] = h_number
            h['build_name']   = h_build
            h.delete 'build'
            h.delete 'number'
          end
          h
        end

        # ---------------------------------------------------------------------------------------------------------------
        def uploadBuildArtifacts()
          @logger.step CLASS+'::'+__method__.to_s
          if @vars.has_key?(:build_dir) and @vars.has_key?(:build_pkg)
            artifacts = @vars[:artifacts] rescue []

            key = getKey()
            if File.exists?(@vars[:build_pkg])
              # Store the assembly - be sure to inherit possible overrides in pkg name and ext but dictate the drawer!
              artifacts << {
                  key:        "#{File.join(File.dirname(key),File.basename(@vars[:build_pkg]))}",
                  data:       {:file => @vars[:build_pkg]},
                  public_url: :build_url,
                  label:      'Package URL'
              }
            else
              @logger.warn "Skipping upload of missing artifact: '#{@vars[:build_pkg]}'"
            end

            # Store the metadata
            manifest = manifestMetadata()
            artifacts << {
                key:        "#{key}.MANIFEST.json",
                data:       {:data => manifest},
                public_url: :manifest_url,
                read_url:   :manifest_url,
                label:      'Manifest URL'
            }

            # Store the checksum
            artifacts << {
                key:        "#{key}.checksum",
                data:       {:data => @vars[:build_sha]},
                public_url: :checksum_url,
                read_url:   :checksum_url,
                label:      'Checksum URL'
            }

            @vars[:return_code] = uploadToRepo(artifacts)
            if 0 == @vars[:return_code]
              @vars[:return_code] = takeInventory()
            end
            @vars[:return_code]
          else
            @vars[:return_code] = Errors::NO_ARTIFACTS
          end
          @vars[:return_code]
        end

        # noinspection RubyHashKeysTypesInspection,RubyHashKeysTypesInspection
        # @param Hash args
        def _getMatches(args, name, match)
          args = args.dup
          args[:version] = '[0-9\.]+'
          args[:release] = '[0-9\.]+'
          args[:build]   = '\d+'
          map = [ :product,:version,:branch,:build ]
          matches = name.match(/^(#{args[:product]})-(#{args[:version]})-(#{args[:branch]})-build-(\d+)$/)
          unless matches
            map = [ :product,:version,:branch,:variant,:build ]
            matches = name.match(/^(#{args[:product]})-(#{args[:version]})-(#{args[:branch]})-(#{args[:variant]})-build-(\d+)$/)
            unless matches
              map = [ :product,:version,:release,:branch,:variant,:build ]
              matches = name.match(/^(#{args[:product]})-(#{args[:version]})-release-(#{args[:release]})-(#{args[:branch]})-(#{args[:variant]})-build-(\d+)$/)
              unless matches
                args[:branch]  = '[^-]+'
                args[:variant] = '[^-]+'
                name = name.dup
                map.each { |key|
                  if key == :release
                    name.gsub!(/^release-/, '')
                  elsif key == :build
                    name.gsub!(/^build-/, '')
                  end
                  if key == match
                    break
                  end
                  # name.gsub!(/^#{args[key]}-/, '')
                  name.gsub!(/^[^\-]+-/, '')
                }
                map.reverse.each { |key|
                  if key == match
                    break
                  end
                  #name.gsub!(/-#{args[key]}$/, '')
                  name.gsub!(/-[^\-]+$/, '')
                  if key == :release
                    name.gsub!(/-release$/, '')
                  elsif key == :build
                    name.gsub!(/-build$/, '')
                  end
                }
                return name
              end
            end
          end
          if matches
            map = Hash[map.map.with_index.to_a]
            if map.has_key? match
              matches[map[match]+1] # 0 is the whole thing
            else
              nil
            end
          else
            nil
          end
        end

        def _getBuildNumber(args,drawer, naming = nil)
          name = drawer['build_name'] rescue drawer['build']
          drawer['build_number'] || _getMatches(args, name, :build)
        end

        def _getVersion(args,drawer, naming = nil)
          name = drawer['build_name'] rescue drawer['build']
          drawer['version'] || _getMatches(args, name, :version)
        end

        def _getRelease(args,drawer, naming = nil)
          name = drawer['build_name'] rescue drawer['build']
          drawer['release'] || _getMatches(args, name, :release)
        end

        def _getBranch(args,drawer, naming = nil)
          name = drawer['build_name'] rescue drawer['build']
          drawer['branch'] || _getMatches(args, name, :branch)
        end

        def release(builds, pruner)
          rel = pruner.shift
          raise "Bad syntax: #{__method__}{ #{pruner.join(' ')}" unless (pruner.size >= 3)
          others = builds.select { |bld|
            bld['release'] != rel
          }
          ours = builds.select { |bld|
            bld['release'] == rel
          }
          ours = prune ours, pruner
          [ others, ours ].flatten.sort_by{ |b| b['build_number'] }
        end

        def version(builds, pruner)
          rel = pruner.shift
          raise "Bad syntax: #{__method__}{ #{pruner.join(' ')}" unless (pruner.size >= 3)
          others = builds.select { |bld|
            ver = _getMatches(@vars, bld['build_name'], :version)
            ver != rel
          }
          ours = builds.select { |bld|
            ver = _getMatches(@vars, bld['build_name'], :version)
            ver == rel
          }
          ours = prune ours, pruner
          [ others, ours ].flatten.sort_by{ |b| b['build_number'] }
        end

        def first(builds, pruner)
          raise "Bad syntax: #{__method__}{ #{pruner.join(' ')}" unless pruner.size == 1
          count = pruner[0].to_i
          count > 0 ? builds[0..(count-1)] : []
        end

        def last(builds, pruner)
          raise "Bad syntax: #{__method__} #{pruner.join(' ')}" unless pruner.size == 1
          count = pruner[0].to_i
          count > 0 ? builds[(-1-count+1)..-1] : []
        end

        def keep(builds, pruner)
          prune builds, pruner
        end

        def drop(builds, pruner)
          raise "Bad syntax: drop #{pruner.join(' ')}" unless pruner.size == 2
          case pruner[0]
          when 'first'
            prune builds, [ 'keep', 'last', pruner[-1] ]
          when 'last'
            prune builds, [ 'keep', 'first', builds.size-pruner[-1].to_i ]
          when /\d+/
            prune builds, [ 'keep', pruner[-2], pruner[-1] ]
          else
            raise "Bad syntax: drop #{pruner.join(' ')}"
          end
        end

        # ---------------------------------------------------------------------------------------------------------------
        def prune(builds, pruner)
          if pruner.size > 0
            blds = builds.dup
            eval("blds = #{pruner[0]} blds, #{pruner[1..-1]}")
            blds
          else
            builds
          end
        end

        # ---------------------------------------------------------------------------------------------------------------
        def analyzeInventory()
          @logger.step __method__.to_s
          # Read and parse in JSON
          key, json, over = pullInventory()
          if json.nil?
            @logger.error "Bad repo/inventory specified. s3://#{ENV['AWS_S3_BUCKET']}/#{key}"
            @vars[:return_code] = Errors::PRUNE_BAD_REPO
          else
            if @vars[:variant]
              if @vars[:tree]
                if @vars[:pruner]
                  if json['container'] and json['container']['variants']
                    # but does not have our variant ...
                    variants = json['container']['variants']
                    variants.each do |variant,varianth|
                      # If the inventory 'latest' format is up to date ...
                      if varianth['latest'] and varianth['latest'].is_a?(Hash)
                        puts "Variant: #{variant}"
                        puts "\t#{varianth['builds'].size} builds"
                        puts "\t#{varianth['branches'].size} branches:\n#{varianth['branches'].ai}"
                        # puts "\t#{varianth['versions'].size} versions:\n#{varianth['versions'].ai}"
                        bmax, bmin, releases, versions, versrels = getVariantVersionsAndReleases(varianth)
                        puts "\t#{versions.size} versions:\n#{versions.ai}"
                        puts "\t#{releases.size} releases:\n#{releases.ai}"
                        puts "\t#{versrels.size} version-releases:\n#{versrels.ai}"
                        puts "\tBuilds: Min: #{bmin}, Max: #{bmax}"
                      else
                        # Start over ... too old/ incompatible
                        @logger.error 'Repo too old or incompatible to prune. No [container][variants][VARIANT][latest].'
                        @vars[:return_code] = Errors::PRUNE_TOO_OLD
                      end
                    end
                  else
                    # Start over ... too old/ incompatible
                    @logger.error 'Repo too old or incompatible to prune. No [container][variants].'
                    @vars[:return_code] = Errors::PRUNE_TOO_OLD
                  end
                else
                  @logger.error "No 'PRUNER' specified"
                  @vars[:return_code] = Errors::PRUNE_NO_PRUNER
                end
              else
                @logger.error "No 'TREE' specified"
                @vars[:return_code] = Errors::PRUNE_NO_TREE
              end
            else
              @logger.error "No 'VARIANT' specified"
              @vars[:return_code] = Errors::PRUNE_NO_VARIANT
            end
          end
          @vars[:return_code]
        end

        # ---------------------------------------------------------------------------------------------------------------
        def getVariantVersionsAndReleases(varianth)
          versions = {}
          releases = {}
          versrels = {}
          bmin = -1
          bmax = -1
          varianth['builds'].each do |bld|
            releases[bld['release']] ||= 0
            releases[bld['release']] += 1
            unless bld['build_number'].nil?
              bnum = bld['build_number'].to_i
              if bmin < 0 or bnum < bmin
                bmin = bnum
              end
              if bnum > bmax
                bmax = bnum
              end
            end
            ver = _getMatches(@vars, bld['build_name'], :version)
            versions[ver] ||= 0
            versions[ver] += 1
            versrels["#{ver}-#{bld['release']}"] ||= 0
            versrels["#{ver}-#{bld['release']}"] += 1
          end
          return bmax, bmin, releases, versions, versrels
        end

        # ---------------------------------------------------------------------------------------------------------------
        def pruneInventory()
          @logger.step __method__.to_s
          # Read and parse in JSON
          key, json, over = pullInventory()
          if json.nil?
            @logger.error "Bad repo/inventory specified. s3://#{ENV['AWS_S3_BUCKET']}/#{key}"
            @vars[:return_code] = Errors::PRUNE_BAD_REPO
          else
            if @vars[:variant]
              if @vars[:tree]
                if @vars[:pruner]
                  if json['container'] and json['container']['variants']
                    # but does not have our variant ...
                    variants = json['container']['variants']
                    if variants[@vars[:variant]]
                      varianth = variants[@vars[:variant]]
                      # If the inventory 'latest' format is up to date ...
                      if varianth['latest'] and varianth['latest'].is_a?(Hash)
                        builds    = varianth['builds']
                        branches  = varianth['branches']
                        versions  = varianth['versions']
                        case @vars[:tree]
                        when %r'variants?'
                          @vars[:pruner].split(/,\s*/).each do |pruner|
                            variants.delete(pruner)
                          end
                        when %r'versions?'
                          @vars[:pruner].split(/,\s*/).each do |pruner|
                            if varianth['versions'].include?(pruner)
                              survivors = varianth['builds'].select{ |drawer|
                                ver = _getVersion(@vars, drawer)
                                ver != pruner
                              }
                              varianth['builds']   = survivors
                              varianth['versions'] = varianth['versions'].select{|ver| ver != pruner }
                            else
                              @logger.error "Cannot prune the version '#{pruner}' from variant '#{@vars[:variant]}'"
                              @vars[:return_code] = Errors::PRUNE_BAD_VERSION
                            end
                          end
                        when %r'branch(|es)'
                          @vars[:pruner].split(/,\s*/).each do |pruner|
                            if varianth['branches'].include?(pruner)
                              survivors = varianth['builds'].select{ |drawer|
                                bra = _getBranch(@vars, drawer)
                                bra != pruner
                              }
                              varianth['builds'] = survivors
                            else
                              @logger.error "Cannot prune the branch '#{pruner}' from variant '#{@vars[:variant]}'"
                              @vars[:return_code] = Errors::PRUNE_BAD_BRANCH
                            end
                          end
                        when %r'builds?'
                          # noinspection RubyHashKeysTypesInspection
                          begin
                            builds = prune(builds, @vars[:pruner].split(/\s+/))
                            varianth['builds']   = builds
                          rescue Exception => e
                            @logger.error "Cannot prune the builds '#{e.message}'"
                            @vars[:return_code] = Errors::PRUNE_BAD_PRUNER
                          end
                        else
                          @logger.error "Bad 'TREE' specified. Only 'branches', 'builds', 'versions' and 'variant' can be pruned"
                          @vars[:return_code] = Errors::PRUNE_NO_TREE
                        end
                        if 0 == @vars[:return_code]
                          _updateBranches(varianth['builds'], varianth)
                          _updateVersions(varianth['builds'], varianth)
                          _updateLatest(varianth)
                          json_s = JSON.pretty_generate( json, { indent: "\t", space: ' '})
                          pushInventory(json_s, key)
                        end
                      else
                        # Start over ... too old/ incompatible
                        @logger.error 'Repo too old or incompatible to prune. No [container][variants][VARIANT][latest].'
                        @vars[:return_code] = Errors::PRUNE_TOO_OLD
                      end
                    else
                      @logger.error "Variant '#{@vars[:variant]}' not present."
                      @vars[:return_code] = Errors::PRUNE_VARIANT_MIA
                    end
                  else
                    # Start over ... too old/ incompatible
                    @logger.error 'Repo too old or incompatible to prune. No [container][variants].'
                    @vars[:return_code] = Errors::PRUNE_TOO_OLD
                  end
                else
                  @logger.error "No 'PRUNER' specified"
                  @vars[:return_code] = Errors::PRUNE_NO_PRUNER
                end
              else
                @logger.error "No 'TREE' specified"
                @vars[:return_code] = Errors::PRUNE_NO_TREE
              end
            else
              @logger.error "No 'VARIANT' specified"
              @vars[:return_code] = Errors::PRUNE_NO_VARIANT
            end
          end
          @vars[:return_code]
        end

        # ---------------------------------------------------------------------------------------------------------------
        def syncRepo()
          @logger.step __method__.to_s
          # Read and parse in JSON
          key, json, over = pullInventory()
          # Starting fresh ?
          if over or json.nil?
            # json_s = initInventory()
            @logger.error "Bad repo/inventory found (s3://#{ENV['AWS_S3_BUCKET']}/#{key}). Inventory may need to be initialized."
            @vars[:return_code] = Errors::SYNC_BAD_REPO
          else
            if json['container'] and json['container']['variants']
              variants = json['container']['variants']
              list = pullRepo()
              s3 = getS3()

              list.each do |obj|
                @logger.debug "Inspect #{obj[:key]}"
                delete = false
                unless obj[:key].match(%r'#{key}$') # It is not INVENTORY.json
                  item = obj[:key].dup
                  if item.match(%r'^#{@vars[:product]}') # Starts as ChefRepo/ for example
                    item.gsub!(%r'^#{@vars[:product]}/', '')
                    matches = item.match(%r'^([^/]+)/') # Next part should be variant i.e. SNAPSHOT
                    if matches
                      variant   = matches[1]
                      if variants.has_key?(variant)
                        varianth = variants[variant]
                        item.gsub!(%r'^#{variant}/', '')
                        #matches = item.match(%r'^([^/]+)/') # Match the drawer name ...
                        drawer,item = File.split(item) # What remains is drawer name and artifact name
                        #if matches
                        if drawer and item
                          # drawer = matches[1]
                          builds = varianth['builds'].select{ |bld|
                            bld['drawer'].eql?(drawer)
                          }
                          if builds.size > 0
                            # item.gsub!(%r'^#{drawer}/', '')

                            if item.match(%r'^#{drawer.match('/') ? drawer.split('/')[0] : drawer}') # Artifact names which start with the drawer name ...
                              name = item.gsub(%r'\.(MANIFEST\.json|tar\.[bg]z2?|tgz|tbz2?|checksum)$', '')
                              ver = _getMatches(@vars, name, :version)
                              rel = _getMatches(@vars, name, :release)
                              bra = _getMatches(@vars, name, :branch)
                              var = _getMatches(@vars, name, :variant)
                              num = _getMatches(@vars, name, :build)
                              # num = num.to_i unless num.nil?
                              #@logger.debug "Variant: #{var}, Version: #{ver}, Branch: #{bra}"
                              unless varianth['versions'].include?(ver) and varianth['branches'].include?(bra) and var.eql?(variant)
                                delete = true
                              else
                                builds = varianth['builds'].select{ |bld|
                                  bld['build_name'].eql?(name)
                                }
                                if builds.size > 0
                                  builds = varianth['builds'].select{ |bld|
                                    bld['release'].eql?(rel)
                                  }
                                  if builds.size > 0
                                    builds = varianth['builds'].select{ |bld|
                                      bld['build_number'] == num
                                    }
                                    unless builds.size > 0
                                      delete = true
                                    end
                                  else
                                    delete = true
                                  end
                                else
                                  delete = true
                                end
                              end
                            end
                          else
                            delete = true
                          end
                        else
                          @logger.warn "Item #{item} drawer cannot be identified!"
                          @vars[:return_code] = Errors::SYNC_NO_DRAWER
                          break
                        end
                      else
                        delete = true
                      end
                    else
                      @logger.warn "Item #{item} variant cannot be identified!"
                      @vars[:return_code] = Errors::SYNC_NO_VARIANT
                      break
                    end
                  else
                    @logger.warn "Item #{item} is not our product(#{@vars[:product]})"
                    @vars[:return_code] = Errors::SYNC_BAD_PRODUCT
                    break
                  end
                  if delete
                    @logger.info "S3 Delete #{ENV['AWS_S3_BUCKET']}, #{obj[:key]}"
                    resp = s3.delete_object(bucket: ENV['AWS_S3_BUCKET'], key: obj[:key])
                    if resp
                      @logger.info "Version: #{resp[:version_id]}" if resp[:version_id]
                    end
                  end
                end
              end
            else
              @logger.error "Bad repo/inventory found (s3://#{ENV['AWS_S3_BUCKET']}/#{key}). Inventory may need to be initialized."
              @vars[:return_code] = Errors::SYNC_BAD_REPO
            end
          end
          @vars[:return_code]
        end

        # ---------------------------------------------------------------------------------------------------------------
        def syncInventory()
          @logger.step __method__.to_s
          # Read and parse in JSON
          key, json, over = pullInventory()
          # Starting fresh ?
          if over or json.nil?
            # json_s = initInventory()
            @logger.error "Bad repo/inventory found (s3://#{ENV['AWS_S3_BUCKET']}/#{key}). Inventory may need to be initialized."
            @vars[:return_code] = Errors::SYNC_BAD_REPO
          else
            list = pullRepo()

            fileroom = {}
            list.each do |obj|
              unless obj[:key].match(%r'#{key}$') # INVENTORY.json ?
                item      = obj[:key].dup
                if item.match(%r'^#{@vars[:product]}') # ChefRepo/....
                  item.gsub!(%r'^#{@vars[:product]}/', '')
                  matches = item.match(%r'^([^/]+)/') # SNAPSHOT/...
                  if matches
                    variant   = matches[1]
                    fileroom[variant] ||= {}
                    cabinet = fileroom[variant]
                    item.gsub!(%r'^#{variant}/', '')
                    #matches = item.match(%r'^([^/]+)/') # Match the drawer name ...
                    drawer,item = File.split(item) # What remains is drawer name and artifact name
                    #if matches
                    if drawer and item
                      # drawer = matches[1]
                      # item.gsub!(%r'^#{drawer}/', '')
                      cabinet[drawer] ||= {}
                      tray = cabinet[drawer]
                      # tray['builds'] ||= {}

                      if item.match(%r'^#{drawer.match('/') ? drawer.split('/')[0] : drawer}') # Artifacts which start with the drawer name
                        name = item.gsub(%r'\.(MANIFEST\.json|tar\.[bg]z2?|tgz|tbz2?|checksum)$', '')
                        ext  = item.gsub(%r'\.(tar\.[bg]z2?)$', '$1')
                        ext  = 'tar.bz2' if ext == item
                        ver = _getMatches(@vars, name, :version)
                        rel = _getMatches(@vars, name, :release)
                        bra = _getMatches(@vars, name, :branch)
                        var = _getMatches(@vars, name, :variant)
                        bld = _getMatches(@vars, name, :build)
                        tray[name] ||= {}
                        filing = tray[name]

                        unless filing.size > 0
                          # noinspection RubyStringKeysInHashInspection
                          filing = _createFiling(json, {
                                                         'drawer'        => drawer,
                                                         'build_name'    => name,
                                                         'build_number'  => bld,
                                                         'release'       => rel,
                                                         'artifacts'     => [obj],
                                                         'build_ext'     => ext,
                                                     } )
                          tray[name] = filing
                          @logger.debug "Filing: #{filing.ai}"
                        else
                          filing['artifacts'] << item # File.basename(obj[:key])
                        end
                      else
                        # Add the artifact to all filings in this drawer :)
                        tray.each do |name,filing|
                          unless filing['drawer'] == drawer
                            @logger.error "#{obj[:key]} belongs in drawer '#{drawer}' which does not match the filings drawer '#{filing['drawer']}'"
                            @vars[:return_code] = Errors::SYNC_NO_DRAWER
                            return @vars[:return_code]
                          end
                          filing['artifacts'] << item # File.basename(obj[:key])
                        end
                      end
                    else
                      @logger.warn "Item #{item} drawer cannot be identified!"
                      @vars[:return_code] = Errors::SYNC_NO_DRAWER
                      break
                    end
                  else
                    @logger.warn "Item #{item} variant cannot be identified!"
                    @vars[:return_code] = Errors::SYNC_NO_VARIANT
                    break
                  end
                else
                  @logger.warn "Item #{item} is not our product(#{@vars[:product]})"
                  @vars[:return_code] = Errors::SYNC_BAD_PRODUCT
                  break
                end
              end
            end
            variants  = {}
            fileroom.each do |variant,cabinet|
              variants[variant]    ||= {}
              varianth = variants[variant]
              varianth['builds']   ||= []
              varianth['branches'] ||= []
              varianth['versions'] ||= []
              cabinet.each do |drawer,tray|
                varianth['builds'] << tray.values.sort_by{ |bld| bld['build_number'].to_i }
                varianth['builds'] = varianth['builds'].flatten
                _updateBranches(varianth['builds'], varianth)
                _updateVersions(varianth['builds'], varianth)
                _updateLatest(varianth)
              end
            end
            if json['container'] and json['container']['variants']
              json['container']['variants'] = variants
              json_s = JSON.pretty_generate( json, { indent: "\t", space: ' '})
              pushInventory(json_s, key)
            end
          end
          @vars[:return_code]
        end

        # ---------------------------------------------------------------------------------------------------------------
        def pullRepo()
          list = []
          s3from = getS3()
          resp = s3from.list_objects(bucket: ENV['AWS_S3_BUCKET'], prefix: @vars[:project_name],)
          if resp and (not resp[:contents].nil?) and resp[:contents].is_a?(Array) and resp[:contents].size > 0
            list << resp[:contents]
            @logger.info "Prefix #{@vars[:project_name]} List size: #{list.flatten.size}"
            if resp[:is_truncated]
              while resp and (not resp[:contents].nil?) and resp[:contents].is_a?(Array) and resp[:contents].size > 0
                resp = s3from.list_objects(bucket: ENV['AWS_S3_BUCKET'], prefix: @vars[:project_name], marker: resp[:contents][-1][:key])
                list << resp[:contents] if resp and resp[:contents]
                @logger.info "Prefix #{@vars[:project_name]} List size: #{list.flatten.size}"
              end
            end
            list.flatten!
          end
          @logger.info "Repo size: #{list.size}"
          list
        end

        # ---------------------------------------------------------------------------------------------------------------
        def _updateLatest(varianth)
          build_lst = (varianth['builds'].size-1)
          build_rel = _getLatestRelease(build_lst, varianth)
          # Latest branch ...
          build_bra = _getLatestBranch(build_lst, varianth)
          # Latest version ...
          build_ver = _getLatestVersion(build_lst, varianth)

          # Set latest
          varianth['latest'] = {
              branch: build_bra,
              version: build_ver,
              build: build_lst,
              release: build_rel,
          }
        end

        # ---------------------------------------------------------------------------------------------------------------
        def _updateVersions(builds, varianth)
          versions = builds.map { |bld|
            _getVersion(@vars, bld)
          }
          # noinspection RubyHashKeysTypesInspection
          varianth['versions'] = Hash[versions.map.with_index.to_a].keys
        end

        # ---------------------------------------------------------------------------------------------------------------
        def _updateBranches(builds, varianth)
          branches = builds.map { |bld|
            _getBranch(@vars, bld)
          }
          # noinspection RubyHashKeysTypesInspection
          varianth['branches'] = Hash[branches.map.with_index.to_a].keys
        end

        protected :_update, :_update, :_updateBranches, :_updateLatest, :_updateVersions

      end
    end
  end
end