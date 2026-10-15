# frozen_string_literal: true

require 'fileutils'
require 'minitest/autorun'
require 'open3'
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

  def test_mixed_version_binaries_keep_legacy_reconciliation
    with_fixture do |root, repo, out, facts_log, parity_log|
      stdout, stderr, status = run_wrapper(root, repo, out, facts_log, parity_log,
                                           facts_typed: true, parity_typed: false)
      assert status.success?, "#{stdout}\n#{stderr}"
      refute_includes File.read(facts_log), '--declarations-out'
      refute_includes File.read(parity_log), '--source-declarations'
      refute File.exist?(File.join(out, 'source-declarations.jsonl'))
    end
  end

  def test_older_facts_binary_keeps_legacy_reconciliation
    with_fixture do |root, repo, out, facts_log, parity_log|
      stdout, stderr, status = run_wrapper(root, repo, out, facts_log, parity_log,
                                           facts_typed: false, parity_typed: true)
      assert status.success?, "#{stdout}\n#{stderr}"
      refute_includes File.read(facts_log), '--declarations-out'
      refute_includes File.read(parity_log), '--target-declarations'
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

  def run_wrapper(root, repo, out, facts_log, parity_log, facts_typed:, parity_typed:, language: 'java')
    facts_bin = File.join(root, 'facts')
    parity_bin = File.join(root, 'parity')
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
        echo "maps-prolog surfaces --bundle-dir #{'--source-declarations --target-declarations' if parity_typed}"
        exit 0
      fi
      printf '%s\\n' "$*" >> "$PARITY_LOG"
    SH
    File.chmod(0o755, facts_bin)
    File.chmod(0o755, parity_bin)
    env = {
      'CHIASMUS_FACTS_BIN' => facts_bin,
      'CHIASMUS_PARITY_BIN' => parity_bin,
      'PORT_RECONCILE_OUT' => out,
      'PORT_RECONCILE_CACHE_DIR' => File.join(root, 'cache'),
      'PORT_INVENTORY' => File.join(root, 'missing-inventory.tsv'),
      'FACTS_LOG' => facts_log,
      'PARITY_LOG' => parity_log
    }
    Open3.capture3(env, 'bash', SCRIPT, repo, 'upstream', language, 'src')
  end
end
