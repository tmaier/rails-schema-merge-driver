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
- Operator-facing diagnostics on every non-clean exit: the executable now
  warns *what* it did (`kept higher version`) or *why it couldn't*
  (`no version conflict detected`) before exiting 1 with conflicts left
  behind, so the auto-resolution behavior is discoverable from a real merge.
- `git merge-file`'s stderr is captured (via `Open3.capture3`) and re-emitted
  on failure, so diagnostics like "Permission denied" or "Cannot merge binary
  files" reach the operator instead of being silently dropped.
- Test coverage for the driver-crash paths (missing args, hard `git
  merge-file` failure, real-world unwritable-file failure) and the
  conflict-remaining warn paths.

### Fixed

- Driver-crash exit code is now ≥ 2 on every bail-out path. `Kernel#abort`
  exits 1, which `git merge-file` treats as "1 conflict remaining" and lets
  git proceed with whatever (potentially garbage) bytes are on disk. All
  bail-outs now use a centralized `bail!(message, code: 2)` helper so future
  contributors can't reintroduce `abort`.
- Hard-failure detection for `git merge-file`. A negative return from its
  `main` is truncated by POSIX to an `exitstatus` greater than 127, so the
  previous `exitstatus.negative?` guard could never fire — letting a hard
  failure surface as a clean driver exit and silently drop the other side's
  changes. Detection now uses `exitstatus > 127` plus `system`'s own nil
  return for the unspawnable-child case.
- Failure messages now name the file being merged (`current.inspect`) so
  during a multi-file merge the operator can tell whether `db/schema.rb` or
  `db/data_schema.rb` blew up.
- `File.read` / `File.write` are wrapped with `SystemCallError` rescues so a
  rare I/O race (chmod/unmount after `git merge-file` succeeded, ENOSPC on
  rewrite) surfaces as a one-line "cannot read/write …" message and exit 2,
  rather than a raw Ruby backtrace exiting 1 — which git would misread as
  "1 conflict remaining" and proceed with whatever bytes are on disk.

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
