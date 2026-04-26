# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Automated, hardened release process. Pushing a `v*` tag now publishes the
  gem to RubyGems.org via [trusted publishing][tp] (OIDC, no long-lived API
  keys) and creates a GitHub Release with the matching CHANGELOG section as
  notes and the built `.gem` attached as an asset, all from
  `.github/workflows/release.yml`.

### Fixed

- Hard-failure detection for `git merge-file`. A negative return from its
  `main` is truncated by POSIX to an `exitstatus` greater than 127, so the
  previous `exitstatus.negative?` guard could never fire — letting a hard
  failure surface as a clean driver exit and silently drop the other side's
  changes. Detection now uses `exitstatus > 127` plus `system`'s own nil
  return for the unspawnable-child case.

[tp]: https://guides.rubygems.org/trusted-publishing/

## [0.1.0] - 2026-04-26

### Added

- Initial release.
- `git-merge-rails-schema` executable: a custom git merge driver that
  auto-resolves the `define(version: N)` conflict in Rails schema files by
  keeping the higher version, and falls back to a normal merge conflict for
  any other diverging content.
- Support for `ActiveRecord::Schema[X.Y].define(version: N)` (`db/schema.rb`)
  and `DataMigrate::Data.define(version: N)` (`db/data_schema.rb` from the
  [data_migrate](https://github.com/ilyakatz/data-migrate) gem).
- Tolerates `merge.conflictstyle = diff3` and `zdiff3` three-section markers.
- Aborts on hard `git merge-file` failures (nil/negative exit) so the other
  side's changes are never silently dropped.

[Unreleased]: https://github.com/tmaier/rails-schema-merge-driver/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/tmaier/rails-schema-merge-driver/releases/tag/v0.1.0
