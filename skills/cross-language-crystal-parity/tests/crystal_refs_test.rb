# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

# Symbol refs (`path::kind::name`) must keep the file-level guarantee and add a
# symbol-level one. Both checks stay backward compatible with plain path refs.
class CrystalRefsTest < Minitest::Test
  SKILL_DIR = File.expand_path('..', __dir__)
  WRAPPER = File.join(SKILL_DIR, 'scripts/check_port_inventory.sh')

  def with_fixture(ref)
    Dir.mktmpdir('crystal-refs-') do |root|
      FileUtils.mkdir_p(File.join(root, 'upstream'))
      FileUtils.mkdir_p(File.join(root, 'src'))
      FileUtils.mkdir_p(File.join(root, 'plans/inventory'))
      File.write(File.join(root, 'upstream/a.go'), "package p\n\nfunc Foo() {}\n")
      File.write(File.join(root, 'src/x.cr'), "def thing\nend\n")
      manifest = File.join(root, 'plans/inventory/go_port_inventory.tsv')
      File.write(manifest, <<~TSV)
        # source_id\tkind\tstatus\tcrystal_refs\tnotes
        a.go::func::Foo\tfunc\tported\t#{ref}\tnote
      TSV
      yield root, manifest
    end
  end

  def check(root, manifest, extra_env = {})
    env = { 'PORT_PARSER' => 'regex' }.merge(extra_env)
    Open3.capture3(env, WRAPPER, root, manifest, 'upstream', 'go')
  end

  def test_symbol_ref_passes_file_and_syntax_checks
    with_fixture('src/x.cr::method::thing') do |root, manifest|
      out, err, status = check(root, manifest)
      assert status.success?, "expected pass, got: #{out}#{err}"
      assert_includes out, 'Port inventory check passed'
    end
  end

  def test_symbol_ref_still_fails_when_the_file_is_gone
    with_fixture('src/gone.cr::method::thing') do |root, manifest|
      _out, err, status = check(root, manifest)
      refute status.success?
      assert_includes err, 'names a missing file'
      assert_includes err, 'src/gone.cr'
    end
  end

  def test_malformed_symbol_ref_is_rejected
    with_fixture('src/x.cr::::thing') do |root, manifest|
      _out, err, status = check(root, manifest)
      refute status.success?
      assert_includes err, 'malformed symbol ref'
    end
  end

  def test_plain_path_refs_keep_working
    with_fixture('src/x.cr') do |root, manifest|
      _out, err, status = check(root, manifest)
      assert status.success?, "expected pass, got: #{err}"
    end
  end

  def test_plus_and_semicolon_refs_are_split
    with_fixture('src/x.cr + src/y.cr; src/z.cr') do |root, manifest|
      %w[src/y.cr src/z.cr].each { |path| File.write(File.join(root, path), "def other\nend\n") }
      _out, err, status = check(root, manifest)
      assert status.success?, "expected multi-ref pass, got: #{err}"
    end
  end

  def test_refs_relative_to_the_first_ref_resolve
    with_fixture('src/deep/x.cr + sibling.cr') do |root, manifest|
      FileUtils.mkdir_p(File.join(root, 'src/deep'))
      File.write(File.join(root, 'src/deep/x.cr'), "def thing\nend\n")
      File.write(File.join(root, 'src/deep/sibling.cr'), "def other\nend\n")
      _out, err, status = check(root, manifest)
      assert status.success?, "expected sibling ref pass, got: #{err}"
    end
  end

  def test_strict_refs_rejects_legacy_separators
    with_fixture('src/x.cr + src/y.cr') do |root, manifest|
      File.write(File.join(root, 'src/y.cr'), "def other\nend\n")
      _out, err, status = check(root, manifest, 'PORT_REF_STRICT' => '1')
      refute status.success?
      assert_includes err, 'must be comma-separated'
    end
  end

  def test_directory_ref_passes_by_default_but_fails_with_require_file
    with_fixture('src') do |root, manifest|
      _out, err, status = check(root, manifest)
      assert status.success?, "expected lenient pass, got: #{err}"

      _out, err, status = check(root, manifest, 'PORT_REQUIRE_FILE' => '1')
      refute status.success?
      assert_includes err, 'names a non-file'
      assert_includes err, 'src'
    end
  end

  def test_crystal_source_verifies_the_symbol_exists
    with_fixture('src/x.cr::method::thing') do |root, manifest|
      _out, err, status = check(root, manifest, 'PORT_CRYSTAL_SOURCE' => 'src')
      assert status.success?, "expected strict pass, got: #{err}"
    end
  end

  def test_crystal_source_rejects_an_unknown_symbol
    with_fixture('src/x.cr::method::nope') do |root, manifest|
      _out, err, status = check(root, manifest, 'PORT_CRYSTAL_SOURCE' => 'src')
      refute status.success?
      assert_includes err, 'unknown Crystal symbol'
      assert_includes err, 'src/x.cr::method::nope'
    end
  end
end
