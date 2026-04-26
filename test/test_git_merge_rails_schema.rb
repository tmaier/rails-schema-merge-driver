# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# Integration tests: drive the executable as a subprocess against synthetic
# three-file inputs, mirroring how git invokes a custom merge driver.
class TestGitMergeRailsSchema < Minitest::Test
  SCRIPT = File.expand_path("../exe/git-merge-rails-schema", __dir__)

  # Writes base/ours/theirs to a tmp dir, runs the driver, yields the resolved
  # `current` (ours) file contents, captured stderr, and the process status.
  def run_driver(base:, ours:, theirs:, conflictstyle: nil, env_overrides: {})
    Dir.mktmpdir do |dir|
      paths = %w[base ours theirs].map { |name| File.join(dir, name) }
      paths.zip([base, ours, theirs]) { |path, content| File.write(path, content) }
      env = if conflictstyle
        {"GIT_CONFIG_COUNT" => "1", "GIT_CONFIG_KEY_0" => "merge.conflictstyle", "GIT_CONFIG_VALUE_0" => conflictstyle}
      else
        {}
      end
      env.merge!(env_overrides)
      _out, err, status = Open3.capture3(env, SCRIPT, *paths, "7")
      yield File.read(paths[1]), status, err
    end
  end

  SCHEMA_BASE = <<~RUBY
    ActiveRecord::Schema[8.1].define(version: 2026_04_01_000000) do
      create_table "users"
    end
  RUBY

  DATA_SCHEMA_BASE = <<~RUBY
    # frozen_string_literal: true

    DataMigrate::Data.define(version: 20_260_400_000_000)
  RUBY

  # --- ActiveRecord::Schema (db/schema.rb) -----------------------------------

  def test_schema_keeps_higher_version_when_ours_is_newer
    ours = SCHEMA_BASE.sub("2026_04_01_000000", "2026_04_20_120000")
    theirs = SCHEMA_BASE.sub("2026_04_01_000000", "2026_04_10_090000")

    run_driver(base: SCHEMA_BASE, ours: ours, theirs: theirs) do |result, status|
      assert_predicate status, :success?
      assert_includes result, "2026_04_20_120000"
      refute_includes result, "2026_04_10_090000"
      refute_includes result, "<<<<<<<"
    end
  end

  def test_schema_keeps_higher_version_when_theirs_is_newer
    ours = SCHEMA_BASE.sub("2026_04_01_000000", "2026_04_10_090000")
    theirs = SCHEMA_BASE.sub("2026_04_01_000000", "2026_04_20_120000")

    run_driver(base: SCHEMA_BASE, ours: ours, theirs: theirs) do |result, status|
      assert_predicate status, :success?
      assert_includes result, "2026_04_20_120000"
      refute_includes result, "<<<<<<<"
    end
  end

  # --- DataMigrate::Data (db/data_schema.rb) ---------------------------------

  def test_data_schema_keeps_higher_version_when_ours_is_newer
    ours = DATA_SCHEMA_BASE.sub("20_260_400_000_000", "20_260_420_120000")
    theirs = DATA_SCHEMA_BASE.sub("20_260_400_000_000", "20_260_410_090000")

    run_driver(base: DATA_SCHEMA_BASE, ours: ours, theirs: theirs) do |result, status|
      assert_predicate status, :success?
      assert_includes result, "20_260_420_120000"
      refute_includes result, "20_260_410_090000"
      refute_includes result, "<<<<<<<"
    end
  end

  def test_data_schema_keeps_higher_version_when_theirs_is_newer
    ours = DATA_SCHEMA_BASE.sub("20_260_400_000_000", "20_260_410_090000")
    theirs = DATA_SCHEMA_BASE.sub("20_260_400_000_000", "20_260_420_120000")

    run_driver(base: DATA_SCHEMA_BASE, ours: ours, theirs: theirs) do |result, status|
      assert_predicate status, :success?
      assert_includes result, "20_260_420_120000"
      refute_includes result, "<<<<<<<"
    end
  end

  # --- conflict-style variants -----------------------------------------------

  def test_zdiff3_conflict_style_still_resolves_version
    ours = SCHEMA_BASE.sub("2026_04_01_000000", "2026_04_20_120000")
    theirs = SCHEMA_BASE.sub("2026_04_01_000000", "2026_04_10_090000")

    run_driver(base: SCHEMA_BASE, ours: ours, theirs: theirs, conflictstyle: "zdiff3") do |result, status|
      assert_predicate status, :success?
      assert_includes result, "2026_04_20_120000"
      refute_includes result, "<<<<<<<"
      refute_includes result, "|||||||"
    end
  end

  # --- real content conflicts (non-version-only) -----------------------------

  def test_real_content_conflict_leaves_markers_and_exits_nonzero
    ours = <<~RUBY
      ActiveRecord::Schema[8.1].define(version: 2026_04_20_120000) do
        create_table "users"
        create_table "books"
      end
    RUBY
    theirs = <<~RUBY
      ActiveRecord::Schema[8.1].define(version: 2026_04_10_090000) do
        create_table "users"
        create_table "authors"
      end
    RUBY

    run_driver(base: SCHEMA_BASE, ours: ours, theirs: theirs) do |result, status, err|
      refute_predicate status, :success?
      assert_equal 1, status.exitstatus, "real content conflicts must exit 1 (recoverable), not 2 (driver crash)"
      assert_includes result, "<<<<<<<"
      # Either "kept higher version" (two hunks) or "no version conflict
      # detected" (one merged hunk) is acceptable — git's hunk packing
      # depends on context-line spacing — but the driver should always
      # explain itself when leaving conflicts behind.
      assert_match(/git-merge-rails-schema: (kept higher version|no version conflict detected)/, err)
    end
  end

  # Enough common context lines between the version bump and the table change
  # so git produces two distinct conflict regions rather than one merged block.
  # The driver should resolve the version region and leave the table region
  # markered for a human.
  def test_version_and_separate_content_conflict_resolves_only_version
    base = <<~RUBY
      ActiveRecord::Schema[8.1].define(version: 2026_04_01_000000) do
        create_table "users"
        create_table "accounts"
        create_table "sessions"
        create_table "memberships"
        create_table "invitations"
        create_table "audits"
        create_table "legacy"
      end
    RUBY
    ours = base.sub("2026_04_01_000000", "2026_04_20_120000").sub('create_table "legacy"', 'create_table "books"')
    theirs = base.sub("2026_04_01_000000", "2026_04_10_090000").sub('create_table "legacy"', 'create_table "authors"')

    run_driver(base: base, ours: ours, theirs: theirs) do |result, status, err|
      refute_predicate status, :success?
      assert_equal 1, status.exitstatus
      assert_includes result, "2026_04_20_120000"
      refute_includes result, "2026_04_10_090000"
      assert_includes result, "<<<<<<<"
      assert_includes result, 'create_table "books"'
      assert_includes result, 'create_table "authors"'
      assert_includes err, "kept higher version"
    end
  end

  # --- driver-crash paths (exit 2, never exit 1) -----------------------------

  # Drives the executable with a stub `git` on PATH, so we can simulate
  # arbitrary `git merge-file` exit codes / stderr without actually merging.
  def run_with_stub_git(base:, ours:, theirs:, stub_script:)
    Dir.mktmpdir do |dir|
      stub_bin = File.join(dir, "bin")
      Dir.mkdir(stub_bin)
      stub_path = File.join(stub_bin, "git")
      File.write(stub_path, stub_script)
      File.chmod(0o755, stub_path)

      paths = %w[base ours theirs].map { |name| File.join(dir, name) }
      paths.zip([base, ours, theirs]) { |path, content| File.write(path, content) }

      env = {"PATH" => "#{stub_bin}:#{ENV["PATH"]}"}
      _out, err, status = Open3.capture3(env, SCRIPT, *paths, "7")
      yield File.read(paths[1]), status, err
    end
  end

  def test_missing_args_exits_two_with_usage_message
    _out, err, status = Open3.capture3(SCRIPT)

    refute_predicate status, :success?
    assert_equal 2, status.exitstatus, "missing args is a driver crash, not a recoverable conflict (exit 1 would be misread as '1 conflict remaining')"
    assert_match(/usage: git-merge-rails-schema/, err)
  end

  def test_git_merge_file_hard_failure_exits_two_and_leaves_file_untouched
    original = "# original contents\n"
    stub = <<~SH
      #!/usr/bin/env bash
      exit 200
    SH

    run_with_stub_git(base: "base\n", ours: original, theirs: "theirs\n", stub_script: stub) do |result, status, err|
      assert_equal 2, status.exitstatus, "hard failures must exit 2 — exit 1 would let git proceed with garbage bytes"
      assert_match(/git merge-file failed/, err)
      assert_match(%r{git merge-file failed for ".*/ours"}, err, "failure message should name which file was being merged")
      assert_equal original, result, "ours must be untouched on driver crash"
    end
  end

  def test_git_merge_file_failure_propagates_git_stderr
    stub = <<~SH
      #!/usr/bin/env bash
      echo "error: cannot merge binary files" >&2
      exit 200
    SH

    run_with_stub_git(base: "base\n", ours: "ours\n", theirs: "theirs\n", stub_script: stub) do |_result, status, err|
      assert_equal 2, status.exitstatus
      assert_includes err, "cannot merge binary files"
    end
  end

  def test_unwritable_target_file_surfaces_git_diagnostic
    # POSIX permission checks are bypassed when euid == 0 (e.g. CI containers
    # running as root), so chmod 0o444 wouldn't actually deny writes. Skip
    # rather than report a false pass.
    skip "permission checks bypassed when running as root" if Process.uid.zero?

    # End-to-end check that real `git merge-file` errors (here: an unwritable
    # target file) surface to the operator with both the "git merge-file
    # failed" framing AND git's own diagnostic — not a silent driver crash.
    Dir.mktmpdir do |dir|
      ours_with_conflict = SCHEMA_BASE.sub("2026_04_01_000000", "2026_04_20_120000")
      theirs_with_conflict = SCHEMA_BASE.sub("2026_04_01_000000", "2026_04_10_090000")
      paths = %w[base ours theirs].map { |name| File.join(dir, name) }
      paths.zip([SCHEMA_BASE, ours_with_conflict, theirs_with_conflict]) { |path, content| File.write(path, content) }
      File.chmod(0o444, paths[1])

      _out, err, status = Open3.capture3(SCRIPT, *paths, "7")

      assert_equal 2, status.exitstatus
      assert_match(/git merge-file failed/, err)
      assert_match(/Permission denied/, err, "real git stderr must reach the operator (Open3 capture)")
    ensure
      File.chmod(0o644, paths[1]) if paths && File.exist?(paths[1])
    end
  end
end
