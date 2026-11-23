# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class GoNativeKindsTest < Minitest::Test
  SKILL_DIR = File.expand_path('..', __dir__)
  API = <<~GO
    package parity

    const ApiVersion = 1
    type Counter int
    type Widget struct {
      Value int
    }
    type Runner interface {
      Run()
    }
    func NewWidget() *Widget {
      return &Widget{}
    }
    func (w *Widget) Run() {
      NewWidget()
    }
  GO
  MANIFESTS = {
    'source.tsv' => %w[generate_source_parity_manifest.sh check_source_parity.sh],
    'port.tsv' => %w[generate_port_inventory.sh check_port_inventory.sh]
  }.freeze
  KIND_HEADER = '# kinds=class,const,func,function,interface,method,struct,type'

  def test_strict_tree_sitter_manifests_retain_go_declarations_and_exclude_auxiliary_captures
    resolver = File.join(SKILL_DIR, 'scripts/resolve_toolchain.py')
    toolchain, err, status = Open3.capture3('python3', resolver, '--require-capability', 'discover.tree-sitter')
    skip "verified Chiasmus discovery toolchain unavailable: #{err.strip}" unless status.success?

    with_fixture(API) do |root|
      binary = File.join(toolchain.strip, Gem.win_platform? ? 'chiasmus-discover.exe' : 'chiasmus-discover')
      raw, err, status = Open3.capture3(binary, '--language', 'go', '--dir', File.join(root, 'upstream'),
                                       '--parser', 'tree-sitter')
      assert status.success?, err
      raw_ids = raw.lines.reject { |line| line.start_with?('#') }.map { |line| line.split("\t", 2).first }
      %w[definition.type definition.function definition.method field package params reference.call reference.class].each do |kind|
        assert raw_ids.any? { |id| id.include?("::#{kind}::") }, "fixture must emit native #{kind} captures"
      end

      expected_ids = %w[
        api.go::class::Widget
        api.go::const::ApiVersion
        api.go::function::NewWidget
        api.go::interface::Runner
        api.go::method::Widget.Run
        api.go::type::Counter
      ]
      MANIFESTS.each do |name, (generate, check)|
        manifest = File.join(root, name)
        assert_success generate, root, manifest, parser: 'tree-sitter'
        assert_equal expected_ids, rows(manifest).map(&:first)
        status_column = name == 'port.tsv' ? 2 : 1
        assert rows(manifest).all? { |row| row[status_column] == 'missing' },
               'native discovery status leaked into the generated manifest'
        assert_includes File.readlines(manifest, chomp: true), KIND_HEADER
        metadata = JSON.parse(File.read("#{manifest}.metadata.json"))
        assert_equal 'chiasmus-tree-sitter', metadata.fetch('backend')
        assert_success check, root, manifest, parser: 'tree-sitter'

        id = 'api.go::interface::Runner'
        File.write(manifest, File.readlines(manifest).reject { |line| line.start_with?("#{id}\t") }.join)
        assert_missing check, root, manifest, id, parser: 'tree-sitter'
      end
    end
  end

  def test_generated_scopes_detect_kinds_added_after_the_baseline
    with_fixture("package parity\n\nconst ApiVersion = 1\n") do |root|
      MANIFESTS.each do |name, (generate, check)|
        manifest = File.join(root, name)
        assert_success generate, root, manifest, parser: 'regex'
        assert_includes File.readlines(manifest, chomp: true), KIND_HEADER
        assert_equal ['api.go::const::ApiVersion'], rows(manifest).map(&:first)
        assert_success check, root, manifest, parser: 'regex'
      end

      File.write(File.join(root, 'upstream/new.go'), "package parity\n\nfunc Added() {}\n")
      MANIFESTS.each do |name, (_, check)|
        assert_missing check, root, File.join(root, name), 'new.go::func::Added', parser: 'regex'
      end
    end
  end

  def test_historical_regex_ids_and_narrow_legacy_kind_scope_still_work
    with_fixture(API) do |root|
      MANIFESTS.each do |name, (generate, check)|
        manifest = File.join(root, name)
        assert_success generate, root, manifest, parser: 'regex'
        assert_equal %w[
          api.go::const::ApiVersion
          api.go::func::NewWidget
          api.go::method::Widget.Run
          api.go::struct::Widget
          api.go::type::Counter
          api.go::type::Runner
        ], rows(manifest).map(&:first)

        const_row = File.readlines(manifest).find { |line| line.start_with?('api.go::const::ApiVersion') }
        File.write(manifest, const_row)
        assert_success check, root, manifest, parser: 'regex'

        File.write(manifest, "# kinds=const\n#{const_row}")
        assert_success check, root, manifest, parser: 'regex'
      end
    end
  end

  def test_checks_reject_invalid_kind_headers_and_out_of_scope_rows
    with_fixture(API) do |root|
      manifest = File.join(root, 'source.tsv')
      _, check = MANIFESTS.fetch('source.tsv')
      const_row = "api.go::const::ApiVersion\tmissing\t-\tbaseline\n"

      {
        "# kinds=\n" => 'Invalid # kinds= header',
        "# kinds=const,\n" => 'Invalid # kinds= header',
        "# kinds=const\n# kinds=func\n" => 'Duplicate # kinds= header'
      }.each do |header, message|
        File.write(manifest, header + const_row)
        _out, err, status = run_script(check, root, manifest, parser: 'regex')
        refute status.success?, "#{check} accepted #{header.inspect}"
        assert_includes err, message
      end

      File.write(manifest, "# kinds=const\n#{const_row}api.go::func::NewWidget\tmissing\t-\tbaseline\n")
      _out, err, status = run_script(check, root, manifest, parser: 'regex')
      refute status.success?, "#{check} accepted a row outside the declared kind scope"
      assert_includes err, 'Source parity manifest has stale entries:'
      assert_includes err, 'api.go::func::NewWidget'
    end
  end

  private

  def with_fixture(api)
    Dir.mktmpdir('go-native-kinds-') do |root|
      FileUtils.mkdir_p(File.join(root, 'upstream'))
      File.write(File.join(root, 'upstream/api.go'), api)
      File.write(File.join(root, 'upstream/api_test.go'), <<~GO)
        package parity

        import "testing"

        func TestSmoke(t *testing.T) {}
      GO
      yield root
    end
  end

  def rows(manifest)
    File.readlines(manifest, chomp: true).reject { |line| line.start_with?('#') }.map { |line| line.split("\t") }
  end

  def run_script(script, root, manifest, parser:)
    env = {
      'PORT_PARSER' => parser,
      'PORT_RECONCILE_CACHE_DIR' => File.join(root, 'cache'),
      'PORT_SCOPE_INCLUDE' => nil,
      'PORT_SCOPE_EXCLUDE' => nil
    }
    Open3.capture3(env, File.join(SKILL_DIR, 'scripts', script), root, manifest, 'upstream', 'go')
  end

  def assert_success(script, root, manifest, parser:)
    out, err, status = run_script(script, root, manifest, parser: parser)
    assert status.success?, "#{out}\n#{err}"
    backend = parser == 'tree-sitter' ? 'chiasmus-tree-sitter' : 'regex'
    assert_includes err, "PARITY_DISCOVERY_BACKEND=#{backend}"
  end

  def assert_missing(script, root, manifest, id, parser:)
    out, err, status = run_script(script, root, manifest, parser: parser)
    refute status.success?, "#{script} accepted #{manifest} without #{id}: #{out}\n#{err}"
    assert_includes err, "  - #{id}"
  end
end
