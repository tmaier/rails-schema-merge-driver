# frozen_string_literal: true

require_relative "lib/rails_schema_merge_driver/version"

Gem::Specification.new do |spec|
  spec.name = "rails-schema-merge-driver"
  spec.version = RailsSchemaMergeDriver::VERSION
  spec.authors = ["Tobias Maier"]
  spec.email = ["tobias.maier@baucloud.com"]

  spec.summary = "Git merge driver that auto-resolves Rails schema version conflicts."
  spec.description = "A custom git merge driver that auto-resolves the most common conflict in Rails schema files (db/schema.rb and, with the data_migrate gem, db/data_schema.rb): the define(version: N) line that gets bumped on every migration. Keeps the higher version on conflict and falls back to a normal merge conflict for any other diverging content. Adapted from tpope's gist (https://gist.github.com/tpope/643979) and extracted from the Librario application (https://www.librario.de)."
  spec.homepage = "https://github.com/tmaier/rails-schema-merge-driver"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = "#{spec.homepage}/blob/main/README.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # External (non-Ruby) requirement: the driver shells out to `git merge-file`,
  # so a working git installation must be on PATH. Informational only — surfaced
  # in `gem info` and `gem specification`; rubygems does not enforce this.
  spec.requirements << "git (with `git merge-file` support)"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = ["git-merge-rails-schema"]
  spec.require_paths = ["lib"]

  spec.extra_rdoc_files = %w[README.md CHANGELOG.md LICENSE.txt].select { |f| File.exist?(File.join(__dir__, f)) }

  spec.post_install_message = <<~MSG
    Thanks for installing rails-schema-merge-driver!

    The gem ships an executable but does not activate itself. To finish setup
    in your Rails project, add to .gitattributes:

      db/schema.rb       merge=rails-schema
      db/data_schema.rb  merge=rails-schema   # only with the data_migrate gem

    Then register the driver in your repo's .git/config:

      git config --local merge.rails-schema.name 'keep newer Rails schema version'
      git config --local merge.rails-schema.driver 'git-merge-rails-schema %O %A %B %L'

    See the README for the full setup, including how to wire this into bin/setup
    so every contributor's clone is configured automatically:
    https://github.com/tmaier/rails-schema-merge-driver
  MSG
end
