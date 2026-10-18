# frozen_string_literal: true

require 'fileutils'
require 'digest'
require 'json'
require 'minitest/autorun'
require 'open3'
require 'rbconfig'
require 'tmpdir'

class ReconcileParitySidecarsTest < Minitest::Test
  SCRIPT = File.expand_path('../scripts/reconcile_parity.sh', __dir__)

  def test_compatible_binaries_export_and_join_typed_sidecars
    with_fixture do |root, repo, out, facts_log, parity_log|
      stdout, stderr, status = run_wrapper(root, repo, out, facts_log, parity_log,
                                           facts_typed: true, parity_typed: true)
      assert status.success?, "#{stdout}\n#{stderr}"

      facts_calls = File.readlines(facts_log)
      assert_equal 2, facts_calls.size
      assert_includes facts_calls[0], "--declarations-out #{out}/source-declarations.jsonl"
      assert_includes facts_calls[1], "--declarations-out #{out}/target-declarations.jsonl"
      assert File.file?(File.join(out, 'source-declarations.jsonl'))
      assert File.file?(File.join(out, 'target-declarations.jsonl'))
      parity_call = File.read(parity_log)
      assert_includes parity_call, "--source-declarations #{out}/source-declarations.jsonl"
      assert_includes parity_call, "--target-declarations #{out}/target-declarations.jsonl"
      assert_includes parity_call, "--bundle-dir #{out}"
    end
  end

  def test_mixed_version_binaries_are_rejected
    with_fixture do |root, repo, out, facts_log, parity_log|
      stdout, stderr, status = run_wrapper(root, repo, out, facts_log, parity_log,
                                           facts_typed: true, parity_typed: false)
      refute status.success?, "#{stdout}\n#{stderr}"
    end
  end

  def test_older_facts_binary_is_rejected
    with_fixture do |root, repo, out, facts_log, parity_log|
      stdout, stderr, status = run_wrapper(root, repo, out, facts_log, parity_log,
                                           facts_typed: false, parity_typed: true)
      refute status.success?, "#{stdout}\n#{stderr}"
    end
  end

  def test_unsupported_source_language_keeps_legacy_reconciliation
    with_fixture do |root, repo, out, facts_log, parity_log|
      stdout, stderr, status = run_wrapper(root, repo, out, facts_log, parity_log,
                                           facts_typed: true, parity_typed: true, language: 'typescript')
      assert status.success?, "#{stdout}\n#{stderr}"
      refute_includes File.read(facts_log), '--declarations-out'
      refute_includes File.read(parity_log), '--source-declarations'
    end
  end

  def test_bundle_cache_flag_is_used_only_when_parity_binary_supports_it
    with_fixture do |root, repo, out, facts_log, parity_log|
      _stdout, stderr, status = run_wrapper(root, repo, out, facts_log, parity_log,
                                            facts_typed: true, parity_typed: true, parity_cache: true)
      assert status.success?, stderr
      assert_includes File.read(parity_log), "--cache-dir #{root}/cache"
    end
    with_fixture do |root, repo, out, facts_log, parity_log|
      _stdout, stderr, status = run_wrapper(root, repo, out, facts_log, parity_log,
                                            facts_typed: true, parity_typed: true, parity_cache: false)
      assert status.success?, stderr
      refute_includes File.read(parity_log), '--cache-dir'
    end
  end

  private

  def with_fixture
    Dir.mktmpdir('parity-sidecars-') do |root|
      repo = File.join(root, 'repo')
      out = File.join(root, 'out')
      facts_log = File.join(root, 'facts.log')
      parity_log = File.join(root, 'parity.log')
      FileUtils.mkdir_p(File.join(repo, 'upstream'))
      FileUtils.mkdir_p(File.join(repo, 'src'))
      File.write(File.join(repo, 'upstream', 'source.txt'), 'source')
      File.write(File.join(repo, 'src', 'target.txt'), 'target')
      yield root, repo, out, facts_log, parity_log
    end
  end

  def run_wrapper(root, repo, out, facts_log, parity_log, facts_typed:, parity_typed:, parity_cache: false, language: 'java')
    toolchain = File.join(root, 'toolchain')
    FileUtils.mkdir_p(File.join(toolchain, 'grammars'))
    facts_bin = File.join(toolchain, 'chiasmus-facts')
    parity_bin = File.join(toolchain, 'chiasmus-parity')
    File.write(facts_bin, <<~SH)
      #!/bin/sh
      if [ "$1" = "--help" ]; then
        echo "--cache-dir #{'--declarations-out' if facts_typed}"
        exit 0
      fi
      printf '%s\\n' "$*" >> "$FACTS_LOG"
      while [ "$#" -gt 0 ]; do
        if [ "$1" = "--declarations-out" ]; then shift; printf '%s\\n' '{"declarations":[]}' > "$1"; fi
        shift
      done
      echo 'defines(source).'
    SH
    File.write(parity_bin, <<~SH)
      #!/bin/sh
      if [ "$1" = "--help" ]; then
        echo "maps-prolog surfaces --bundle-dir #{'--cache-dir' if parity_cache} #{'--source-declarations --target-declarations' if parity_typed}"
        exit 0
      fi
      printf '%s\\n' "$*" >> "$PARITY_LOG"
    SH
    File.chmod(0o755, facts_bin)
    File.chmod(0o755, parity_bin)
    %w[discover plan complete].each do |name|
      path = File.join(toolchain, "chiasmus-#{name}")
      File.write(path, "#!/bin/sh\nexit 0\n")
      File.chmod(0o755, path)
    end
    os = RbConfig::CONFIG['host_os'] =~ /darwin/ ? 'darwin' : 'linux'
    extension = os == 'darwin' ? 'dylib' : 'so'
    %w[java go crystal].each { |name| File.write(File.join(toolchain, 'grammars', "libtree-sitter-#{name}.#{extension}"), name) }
    cpu = `uname -m`.strip =~ /arm64|aarch64/ ? 'aarch64' : 'x86_64'
    platform = "#{os}-#{cpu}"
    files = Dir.glob(File.join(toolchain, '**', '*')).select { |path| File.file?(path) }.to_h do |path|
      [path.delete_prefix("#{toolchain}/"), { sha256: Digest::SHA256.file(path).hexdigest, size: File.size(path) }]
    end
    manifest = { manifest_version: 1, platform: platform, build_id: 'fixture', files: files,
                 capabilities: { facts: ['typed-declarations'], parity: ['bundle'] } }
    File.write(File.join(toolchain, 'toolchain-manifest.json'), JSON.generate(manifest))
    env = {
      'CHIASMUS_TOOLCHAIN_DIR' => toolchain,
      'PORT_RECONCILE_OUT' => out,
      'PORT_RECONCILE_CACHE_DIR' => File.join(root, 'cache'),
      'PORT_INVENTORY' => File.join(root, 'missing-inventory.tsv'),
      'FACTS_LOG' => facts_log,
      'PARITY_LOG' => parity_log
    }
    Open3.capture3(env, 'bash', SCRIPT, repo, 'upstream', language, 'src')
  end
end
