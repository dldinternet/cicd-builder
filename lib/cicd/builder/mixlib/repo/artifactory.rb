require 'aws-sdk-core'
require 'aws-sdk-resources'

module CiCd
	module Builder
    module Repo
      module Artifactory
        # ---------------------------------------------------------------------------------------------------------------
        def getS3()
          region = ENV['AWS_REGION'] || ::Aws.config[:region] || 'us-east-1'
          unless @s3
            @s3 = ::Aws::S3::Client.new(             region: region)
          end
          unless @s3 and ((@s3.config.access_key_id and @s3.config.secret_access_key) or @s3.config.credentials)
            @logger.warn "Unable to find AWS credentials in standard locations:
ENV['AWS_ACCESS_KEY'] and ENV['AWS_SECRET_ACCESS_KEY']
Aws.config[:credentials]
Shared credentials file, ~/.aws/credentials
EC2 Instance profile\n"
            if ENV['AWS_PROFILE']
              @logger.info "Trying profile '#{ENV['AWS_PROFILE']}'"
              creds = Aws::SharedCredentials.new( path: File.expand_path('~/.aws/credentials'), profile: ENV['AWS_PROFILE'] )
              if creds.loadable?
                @s3 = ::Aws::S3::Client.new(region: region, credentials: creds)
              end
            end
          end
          unless @s3 and ((@s3.config.access_key_id and @s3.config.secret_access_key) or @s3.config.credentials)
            raise 'Unable to find AWS credentials!'
          end
          @s3
        end

        # ---------------------------------------------------------------------------------------------------------------
        def uploadToRepo(artifacts)
          s3 = getS3()
          artifacts.each{|art|

            s3_obj = maybeS3Object(art[:key], s3)
            upload = false
            if art[:data].has_key?(:file)
              md5 = Digest::MD5.file(art[:data][:file]).hexdigest
            else
              #noinspection RubyArgCount
              md5 = Digest::MD5.hexdigest(art[:data][:data])
            end
            if s3_obj.nil?
              upload = true
            else
              @logger.info "s3://#{ENV['AWS_S3_BUCKET']}/#{art[:key]} exists"
              etag = s3_obj.etag.gsub(/"/, '')
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
                size = art[:data][:data].length
                body = art[:data][:data]
              end
              art[:data][:metadata] = {checksum: md5, digest: "md5=#{md5}"}
              # art[:data][:'x-amz-meta-digest'] = "md5=#{md5}"
              res = s3.put_object(         bucket: ENV['AWS_S3_BUCKET'],
                                           key: art[:key],
                                           body: body,
                                           # acl: 'authenticated-read',
                                           content_length: size,
                                           #    content_md5: md5,
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
          end
          s3_obj
        end

        # ---------------------------------------------------------------------------------------------------------------
        def initInventory()

          hash =
              {
                  id:   "#{@vars[:project_name]}",
                  #  In case future generations introduce incompatible features
                  gen:  "#{@options[:gen]}",
                  container:  {
                      artifacts: %w(assembly metainfo checksum),
                      naming: '<product>-<major>.<minor>.<patch>-<branch>-release-<number>-build-<number>.<extension>',
                      assembly: {
                          extension:  'tar.gz',
                          type:       'targz'
                      },
                      metainfo: {
                          extension:  'MANIFEST.json',
                          type:       'json'
                      },
                      checksum: {
                          extension:  'checksum',
                          type:       'Digest::SHA256'
                      },
                      variants: {
                          :"#{@vars[:variant]}" => {
                              latest: {
                                  build:   0,
                                  branch:  0,
                                  version: 0,
                                  release: 0,
                              },
                              versions: [ "#{@vars[:build_ver]}" ],
                              branches: [ "#{@vars[:build_bra]}" ],
                              builds: [
                                  {
                                      drawer:       @vars[:build_nam],
                                      build_name:   @vars[:build_rel],
                                      build_number: @vars[:build_num],
                                      release:      @vars[:release],
                                  }
                              ],
                          }
                      }
                  }
              }
          artifacts = getArtifactsDefinition()
          naming    = getNamingDefinition()

          # By default we use the internal definition ...
          if artifacts
            artifacts.each do |name,artifact|
              hash[:container][name] = artifact
            end
          end

          # By default we use the internal definition ...
          if naming
            hash[:container][:naming] = naming
          end
          JSON.pretty_generate( hash, { indent: "\t", space: ' '})
        end

        # ---------------------------------------------------------------------------------------------------------------
        def takeInventory()
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

          # Read and parse in JSON
          json_s    = ''
          json      = nil
          varianth  = nil

          key    = "#{@vars[:project_name]}/INVENTORY.json"
          s3_obj = maybeS3Object(key)
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
            version    = ::Semverse::Version.new(json['gen'])
            # raise CiCd::Builder::Errors::InvalidVersion.new "The constraint failed: #{json['gen']} #{constraint}"

            unless constraint.satisfies?(version)
              raise CiCd::Builder::Errors::InvalidVersion.new "The inventory generation is newer than I can manage: #{version} <=> #{@options[:gen]}"
            end
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
            unless varianth['builds'].map { |b| b['build_name'] }.include?(@vars[:build_rel])
              #noinspection RubyStringKeysInHashInspection
              filing = {
                  'drawer'        => @vars[:build_nam],
                  'build_name'    => @vars[:build_rel],
                  'build_number'  => @vars[:build_num],
                  'release'       => @vars[:release],
              }
              if @vars.has_key?(:artifacts)
                filing['artifacts'] = @vars[:artifacts].map { |artifact| File.basename(artifact[:key]) }
              end
              assembly = json['container']['assembly'] or raise("Expected an 'assembly'")
              if assembly['extension'] != !vars[:build_ext]
                # noinspection RubyStringKeysInHashInspection
                filing['assembly'] = {
                    'extension' => @vars[:build_ext],
                    'type'      => 'tarbzip2'
                }
              end
              varianth['builds'] << filing
            end
            build_lst = (varianth['builds'].size-1)
            build_rel = build_lst
            i = -1
            varianth['builds'].each{ |h|
              i += 1
              convert_build(h)
              convert_build(varianth['builds'][build_rel])
              if h['release'].to_i > varianth['builds'][build_rel]['release'].to_i
                build_rel = i
              elsif h['release'] == varianth['builds'][build_rel]['release']
                build_rel = i if h['build_number'].to_i > varianth['builds'][build_rel]['build_number'].to_i
              end
            }

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
          begin
            md5 = Digest::MD5.hexdigest(json_s)
            # [:'x-amz-meta-digest'] = "md5=#{md5}"
            resp = getS3.put_object(    bucket: ENV['AWS_S3_BUCKET'],
                                        key: key,
                                        body: json_s,
                                        # acl: 'authenticated-read',
                                        metadata: {checksum: md5, digest: "md5=#{md5}"},
            )
            s3_obj = maybeS3Object(key)
            s3_obj.etag
            @logger.info "Inventory URL: #{s3_obj.presigned_url(:get, expires_in: 86400)}"
            return 0
          rescue Exception => e
            @logger.error("Exception: #{e.class.name}: #{e.message}\n#{e.backtrace.ai}")
            return -1
          end
        end

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
        def getKey
          key = "#{@vars[:project_name]}/#{@vars[:variant]}/#{@vars[:build_nam]}/#{@vars[:build_rel]}"
        end

      end
    end
  end
end