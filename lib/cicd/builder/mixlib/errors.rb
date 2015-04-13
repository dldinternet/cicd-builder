module CiCd
	module Builder
		module Errors

			class Unknown < StandardError ; end
			class Internal < Unknown ; end
			class InvalidVersion < Unknown ; end
			class InvalidVersionConstraint < Unknown ; end

      i = 10
      ARTIFACT_UPLOAD_EXCEPTION   = i+=1
      ARTIFACT_NOT_UPLOADED       = i+=1
      ARTIFACT_NOT_COPIED         = i+=1
      MAKEBUILD_EXCEPTION         = i+=1
      MAKEBUILD_PREPARATION       = i+=1
      MISSING_ENV_VAR             = i+=1
      PREPAREBUILD_EXCEPTION      = i+=1
      PARSING_LATEST_VERSION      = i+=1
      PARSING_BUILD_CHECKSUM      = i+=1
      STORING_BUILD_CHECKSUM      = i+=1
      INVALID_WORKSPACE           = i+=1
      CLEANUPBUILD_EXCEPTION      = i+=1
      REPO_DIR                    = i+=1
      WORKSPACE_DIR               = i+=1
      NO_COMPONENTS               = i+=1
      MANIFEST_EMPTY              = i+=1
      MANIFEST_WRITE              = i+=1
      MANIFEST_DELETE             = i+=1
      INVENTORY_UPLOAD_EXCEPTION  = i+=1
      STORING_BUILD_METADATA      = i+=1
      BUILDER_REPO_TYPE           = i+=1
      BUILD_DIR                   = i+=1
      BUCKET                      = i+=1
      BAD_ARTIFACTS               = i+=1
      ARTIFACT_NOT_FOUND          = i+=1
      SAVE_LATEST_VARS            = i+=1
      SAVE_ENVIRONMENT_VARS       = i+=1
      NO_ARTIFACTS                = i+=1
      NO_PROJECT_NAMES            = i+=1
      NO_PROJECTS_PATH            = i+=1
      TEMP_FILE_MISSING           = i+=1
      PRUNE_BAD_REPO              = i+=1
      PRUNE_NO_TREE               = i+=1
      PRUNE_NO_VARIANT            = i+=1
      PRUNE_NO_PRUNER             = i+=1
      PRUNE_TOO_OLD               = i+=1
      PRUNE_VARIANT_MIA           = i+=1
      PRUNE_BAD_BRANCH            = i+=1
      PRUNE_BAD_VERSION           = i+=1
      PRUNE_BAD_PRUNER            = i+=1
      SYNC_BAD_REPO               = i+=1
      SYNC_BAD_PRODUCT            = i+=1
      SYNC_NO_VARIANT             = i+=1
      SYNC_NO_DRAWER              = i+=1

      require 'awesome_print'

      MAP = {}
      constants.each do |c|
        MAP[const_get(c)] = c.to_s
      end

		end
	end
end