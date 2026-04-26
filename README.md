# rails-schema-merge-driver

[![Gem Version](https://img.shields.io/gem/v/rails-schema-merge-driver.svg)](https://rubygems.org/gems/rails-schema-merge-driver)
[![CI](https://github.com/tmaier/rails-schema-merge-driver/actions/workflows/main.yml/badge.svg)](https://github.com/tmaier/rails-schema-merge-driver/actions/workflows/main.yml)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-standard-brightgreen.svg)](https://github.com/standardrb/standard)

A git custom merge driver that auto-resolves the most common conflict in Rails
schema files — the bumped `define(version: N)` line — by keeping the higher
version. Real content conflicts are left for a human.

## Why

`db/schema.rb` is regenerated on every migration, so the `version:` argument at
the top of the file changes on every concurrent branch. Whenever two branches
add migrations and meet at a merge, git flags this line as a conflict — but it
isn't a real conflict: the right answer is always _the higher version_, which
already implies the union of both migrations.

This driver delegates to git's built-in three-way merge, then post-processes
the resulting conflict region: if the only diverging line is `define(version:
N)`, it picks the higher version and writes the file. Anything else is left as
a normal conflict with markers in place, exiting non-zero so git knows the file
still needs human attention.

## Supported formats

- `ActiveRecord::Schema[X.Y].define(version: N)` — standard Rails `db/schema.rb`.
- `DataMigrate::Data.define(version: N)` — `db/data_schema.rb` from the
  [`data_migrate`](https://github.com/ilyakatz/data-migrate) gem.

Tolerates `merge.conflictstyle = diff3` and `zdiff3` (three-section markers).

## Installation

Add to your Gemfile in the development group:

```ruby
gem "rails-schema-merge-driver", group: :development, require: false
```

`require: false` is important: the gem ships only an executable, so nothing
needs to autoload at app boot. Without it, `Bundler.require` would either fail
looking for a hyphenated path or load `lib/rails_schema_merge_driver.rb`
unnecessarily.

Then `bundle install`. The `git-merge-rails-schema` executable becomes
available under `bundle exec`. For a system install instead:

```sh
gem install rails-schema-merge-driver
```

## Setup (per repository)

The driver needs to be wired in two places: `.gitattributes` (which files it
applies to) and `.git/config` (the driver definition itself, which is _not_
versioned and must be set up by every contributor).

### 1. `.gitattributes`

```gitattributes
db/schema.rb       merge=rails-schema
db/data_schema.rb  merge=rails-schema   # only if you use the data_migrate gem
```

The second line is only needed for projects that depend on the
[`data_migrate`](https://github.com/ilyakatz/data-migrate) gem.

### 2. `.git/config`

Each contributor's clone needs the driver registered. Either run these once:

```sh
git config --local merge.rails-schema.name 'keep newer Rails schema version'
git config --local merge.rails-schema.driver 'git-merge-rails-schema %O %A %B %L'
```

…or — recommended — wire it into your `bin/setup` so every contributor's clone
is configured automatically when they bootstrap the project. Example, adapted
from the [Librario](https://www.librario.de) `bin/setup` (the project this gem
was extracted from):

```ruby
def configure_git_merge_drivers
  system "git config --local merge.rails-schema.name 'keep newer Rails schema version'"
  system "git config --local merge.rails-schema.driver 'git-merge-rails-schema %O %A %B %L'"
end

configure_git_merge_drivers
```

`git config --local` is idempotent, so this is safe to re-run.

If you installed the gem via bundler with `require: false`, you may need to
prefix the driver command with `bundle exec` so the executable is found from
inside the project's gem environment:

```sh
git config --local merge.rails-schema.driver 'bundle exec git-merge-rails-schema %O %A %B %L'
```

## How it works

1. The driver shells out to `git merge-file --marker-size=N current base
   other`, which performs the standard three-way text merge.
2. It reads the result and looks for a conflict region whose only diverging
   line is a `.define(version: N)` call (handling diff3/zdiff3 base sections).
3. If found, it replaces the region with whichever side has the higher numeric
   version (underscores stripped) and writes the file back.
4. Exits 0 if the file is fully resolved (no remaining `<<<<<<<` markers),
   exits 1 otherwise so git surfaces the remaining conflict to the user.

`git merge-file` exit codes are passed through carefully: a hard failure (nil
or negative status) aborts immediately, since silently treating it as
"resolved" would drop the other side's changes.

## Development

```sh
bin/setup            # bundle install
bundle exec rake     # default: test + standard
bundle exec rake test
bundle exec rake standard
```

To experiment in an IRB session:

```sh
bin/console
```

To install this gem onto your local machine, run `bundle exec rake install`.

## Releasing

Releases are published to RubyGems.org via [trusted publishing][tp] (OIDC, no
API keys) by `.github/workflows/release.yml`, triggered when a `v*` tag is
pushed. Steps:

1. Bump `RailsSchemaMergeDriver::VERSION` in
   `lib/rails_schema_merge_driver/version.rb`, then run `bundle exec rake test` so `Gemfile.lock` (which path-references the gem itself) picks up
   the new version.
2. Move the relevant entries from `[Unreleased]` to a new dated section in
   `CHANGELOG.md`, following the [Keep a Changelog][kac] format.
3. Commit `version.rb`, `Gemfile.lock`, and `CHANGELOG.md`; push to `main`;
   wait for CI to pass.
4. Tag and push:
   ```sh
   git tag v0.x.0
   git push origin v0.x.0
   ```

The workflow then:

- Authenticates to RubyGems.org via OIDC (no secrets required).
- Runs `bundle exec rake release` — which builds the gem and pushes it
  (skips re-tagging because the tag already exists, per `bundler/gem_helper.rb`).
- Creates a GitHub Release at the tag with the CHANGELOG section as notes and
  the `.gem` file attached as a downloadable asset.

[tp]: https://guides.rubygems.org/trusted-publishing/
[kac]: https://keepachangelog.com/en/1.1.0/

## Acknowledgements

- Originally extracted from the [Librario](https://www.librario.de)
  application (a Rails-based library management system) where this driver was
  developed and battle-tested.
- Adapted from [tpope's gist](https://gist.github.com/tpope/643979), which
  proposed the original `railsschema` merge-driver idea.
- See [git's gitattributes(5) docs](https://git-scm.com/docs/gitattributes#_defining_a_custom_merge_driver)
  for the full custom merge-driver protocol.

## Contributing

Bug reports and pull requests are welcome on GitHub at
<https://github.com/tmaier/rails-schema-merge-driver>.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
