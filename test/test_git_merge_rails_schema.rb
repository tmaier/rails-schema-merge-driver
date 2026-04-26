# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# Integration tests: drive the executable as a subprocess against synthetic
# three-file inputs, mirroring how git invokes a custom merge driver.
class TestGitMergeRailsSchema < Minitest::Test
  SCRIPT = File.expand_path("../exe/git-merge-rails-schema", __dir__)

  # Writes base/ours/theirs to a tmp dir, runs the driver, yields the resolved
  # `current` (ours) file contents and the process status.
  def run_driver(base:, ours:, theirs:, conflictstyle: nil)
    Dir.mktmpdir do |dir|
      paths = %w[base ours theirs].map { |name| File.join(dir, name) }
      paths.zip([base, ours, theirs]) { |path, content| File.write(path, content) }
      env = if conflictstyle
        {"GIT_CONFIG_COUNT" => "1", "GIT_CONFIG_KEY_0" => "merge.conflictstyle", "GIT_CONFIG_VALUE_0" => conflictstyle}
      else
        {}
      end
      _out, _err, status = Open3.capture3(env, SCRIPT, *paths, "7")
      yield File.read(paths[1]), status
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

    run_driver(base: SCHEMA_BASE, ours: ours, theirs: theirs) do |result, status|
      refute_predicate status, :success?
      assert_includes result, "<<<<<<<"
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

    run_driver(base: base, ours: ours, theirs: theirs) do |result, status|
      refute_predicate status, :success?
      assert_includes result, "2026_04_20_120000"
      refute_includes result, "2026_04_10_090000"
      assert_includes result, "<<<<<<<"
      assert_includes result, 'create_table "books"'
      assert_includes result, 'create_table "authors"'
    end
  end
end
