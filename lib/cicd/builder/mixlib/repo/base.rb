# require 'delegate'
require 'forwardable'

module CiCd
	module Builder
    module Repo

      class Base
        extend ::Forwardable

        attr_reader :builder

        def_delegators :@builder, :options, :vars, :logger, :getBuilderVersion, :calcLocalETag

        # ---------------------------------------------------------------------------------------------------------------
        def initialize(builder)
          @builder  = builder
          @vars     = vars()
          @logger   = logger()
          @options  = options()
        end

        # ---------------------------------------------------------------------------------------------------------------
        def getKey
          key = "#{@vars[:project_name]}/#{@vars[:variant]}/#{@vars[:build_nam]}/#{@vars[:build_nmn]}"
        end

        # ---------------------------------------------------------------------------------------------------------------
        def tempArtifactFile(name,data)
          io = Tempfile.new(name)
          data[:temp] = true
          io.write(data[:data])
          io.close
          data[:file] = io.path
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
                                      build_name:   @vars[:build_nmn],
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

      end
    end
  end
end