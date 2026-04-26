# frozen_string_literal: true

require_relative "rails_schema_merge_driver/version"

# RailsSchemaMergeDriver is a git custom merge driver that auto-resolves the
# common `define(version: N)` conflict in Rails schema files. The gem is
# delivered as a CLI executable (exe/git-merge-rails-schema); this module
# exists primarily to expose VERSION to the gemspec.
#
# See README.md for setup instructions.
module RailsSchemaMergeDriver
end
