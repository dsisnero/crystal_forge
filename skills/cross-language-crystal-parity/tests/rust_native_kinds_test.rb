# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class RustNativeKindsTest < Minitest::Test
  SKILL_DIR = File.expand_path('..', __dir__)
  LIB = File.join(SKILL_DIR, 'scripts/parity_inventory_lib.rb')

  def test_native_and_historical_rust_kinds_survive_source_and_test_manifests
    with_fixture do |root|
      source = File.join(root, 'source.tsv')
      tests = File.join(root, 'tests.tsv')

      out, err, status = run_script('generate_source_parity_manifest.rb',
                                    '--root', root, '--source', 'upstream', '--language', 'rust',
                                    '--parser', 'regex', '--out', source)
      assert status.success?, "#{out}\n#{err}"
      ids = File.readlines(source).drop(1).map { |line| line.split("\t", 2).first }
      %w[func struct enum trait const method].each do |kind|
        assert ids.any? { |id| id.include?("::#{kind}::") }, "missing historical #{kind} from source manifest"
      end
      refute ids.any? { |id| id.include?('::test::') }, 'inline test leaked into source manifest'

      out, err, status = run_script('generate_test_parity_manifest.rb',
                                    '--root', root, '--source', 'upstream', '--language', 'rust',
                                    '--parser', 'regex', '--out', tests)
      assert status.success?, "#{out}\n#{err}"
      test_ids = File.readlines(tests).drop(1).map { |line| line.split("\t", 2).first }
      assert_includes test_ids, 'src/lib.rs::test::smoke'

      out, err, status = run_script('check_source_parity.rb',
                                    '--root', root, '--source', 'upstream', '--language', 'rust',
                                    '--parser', 'regex', '--manifest', source)
      assert status.success?, "#{out}\n#{err}"

      File.write(source, File.readlines(source).reject { |line| line.include?('::func::free_function') }.join)
      out, err, status = run_script('check_source_parity.rb',
                                    '--root', root, '--source', 'upstream', '--language', 'rust',
                                    '--parser', 'regex', '--manifest', source)
      refute status.success?, 'drift checker accepted a source manifest missing a known free function anchor'
      assert_includes err, 'free_function'
    end
  end

  def test_strict_tree_sitter_discovery_preserves_native_rust_kinds
    skip 'verified Chiasmus discovery toolchain unavailable' unless tree_sitter_toolchain_available?

    with_fixture do |root|
      source = File.join(root, 'source.tsv')

      out, err, status = run_script('generate_source_parity_manifest.rb',
                                    '--root', root, '--source', 'upstream', '--language', 'rust',
                                    '--parser', 'tree-sitter', '--out', source)
      assert status.success?, "#{out}\n#{err}"
      assert_includes err, 'PARITY_DISCOVERY_BACKEND=chiasmus-tree-sitter'

      rows = File.readlines(source).drop(1).map { |line| line.chomp.split("\t") }
      ids = rows.map(&:first)
      %w[
        src/lib.rs::const::VALUE
        src/lib.rs::function::free_function
        src/lib.rs::class::Demo
        src/lib.rs::class::Mode
        src/lib.rs::interface::Action
        src/lib.rs::method::Demo.method
      ].each do |id|
        assert_includes ids, id
      end
      refute ids.any? { |id| id.include?('::test::') }, 'inline test leaked into source manifest'
      assert rows.all? { |row| row[1] == 'missing' },
             'native discovery status leaked into the generated source manifest'
    end
  end

  def test_curated_filter_retains_native_and_historical_rust_kinds
    script = <<~'RUBY'
      require ARGV.fetch(0)
      kinds = %w[function class interface func struct enum trait const method test]
      items = kinds.map do |kind|
        ParityInventory::Item.new(id: "x::#{kind}::sample", kind: kind, scope: 'source', file: 'x', name: kind)
      end
      puts ParityInventory.curated_inventory_items(items, language: 'rust').map(&:kind).sort
    RUBY
    out, err, status = Open3.capture3('ruby', '-e', script, LIB)
    assert status.success?, "#{out}\n#{err}"
    assert_equal %w[class const enum func function interface method struct test trait], out.lines.map(&:strip)
  end

  private

  def with_fixture
    Dir.mktmpdir('rust-native-kinds-') do |root|
      FileUtils.mkdir_p(File.join(root, 'upstream/src'))
      File.write(File.join(root, 'upstream/src/lib.rs'), <<~RS)
        pub const VALUE: i32 = 1;
        pub struct Demo;
        pub enum Mode { First }
        pub trait Action { fn apply(&self); }
        pub fn free_function() {}
        impl Demo {
          pub fn method(&self) {}
        }
        #[cfg(test)]
        mod tests {
          #[test]
          fn smoke() {}
        }
      RS
      yield root
    end
  end

  def run_script(script, *args)
    Open3.capture3('ruby', File.join(SKILL_DIR, 'scripts', script), *args)
  end

  def tree_sitter_toolchain_available?
    resolver = File.join(SKILL_DIR, 'scripts/resolve_toolchain.py')
    _out, _err, status = Open3.capture3('python3', resolver, '--require-capability', 'discover.tree-sitter')
    status.success?
  rescue Errno::ENOENT
    false
  end
end
