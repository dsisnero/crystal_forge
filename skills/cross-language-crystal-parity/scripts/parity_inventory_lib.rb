#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'pathname'
require 'rbconfig'
require 'set'

module ParityInventory
  # Languages with a regex extractor (used as the no-grammar fallback).
  SUPPORTED_LANGUAGES = %w[go rust crystal java ruby typescript csharp python].freeze
  # Default curated kinds for any language that lacks an explicit entry below.
  # Broad enough to cover definitional symbols across grammars; per-language
  # entries can narrow it.
  DEFAULT_CURATED_KINDS = Set.new(%w[class const ctor enum func function interface method module record struct test trait type]).freeze
  CURATED_KINDS = {
    'go' => Set.new(%w[const struct type func method test]),
    'rust' => Set.new(%w[const struct enum trait type func method test]),
    'crystal' => Set.new(%w[class module struct enum const func method test]),
    'java' => Set.new(%w[class interface enum record const ctor func method test]),
    'ruby' => Set.new(%w[class module const func method test]),
    'typescript' => Set.new(%w[class const function interface method test type]),
    'csharp' => Set.new(%w[class interface enum record const ctor func method test]),
    'python' => Set.new(%w[class const function method test])
  }.freeze

  Item = Struct.new(:id, :kind, :scope, :file, :name, keyword_init: true)

  module_function

  def resolve_base(root_dir, source_path)
    root = Pathname(root_dir).expand_path
    if source_path && !source_path.strip.empty?
      candidate = Pathname(source_path)
      return candidate.expand_path if candidate.absolute?

      return (root + candidate).expand_path
    end

    vendor = root + 'vendor'
    vendor.exist? ? vendor : root
  end

  def detect_treesitter(language, root_dir = nil)
    return true if grammar_available?(language, root_dir)

    begin
      require 'tree_sitter'
      # Common ruby gem names for language grammars.
      possible = [
        "tree_sitter/#{language}",
        "tree_sitter_#{language}",
        "tree-sitter-#{language}"
      ]
      possible.any? do |lib|
        require lib
        true
      rescue LoadError
        false
      end
    rescue LoadError
      false
    end
  end

  def discover_with_crystal_discovery(base, language, root_dir: nil, fallback: true)
    discover_bin = discover_crystal_binary(root_dir)
    unless discover_bin
      message = "Crystal discovery binary not found"
      raise RuntimeError, message unless fallback

      warn "#{message}; falling back to regex"
      return [discover_with_regex(base, language), 'regex', nil]
    end

    begin
      command = Array(discover_bin) + ['--language', language, '--dir', base.to_s, '--parser', 'tree-sitter']
      output = IO.popen(command, &:read)
      status = $?
      unless status&.success?
        raise RuntimeError, "Crystal discovery exited #{status&.exitstatus}: #{output.strip}"
      end
      items = []
      reported_parsers = Set.new
      output.each_line do |line|
        next if line.start_with?('#') || line.strip.empty?
        cols = line.split("\t", -1)
        next unless cols.length >= 2

        parser = cols[4].to_s[/parser=([^\s]+)/, 1]
        reported_parsers << parser if parser

        source_id = cols[0].strip
        kind = cols[1].strip
        # Parse the ID format: {file}::{kind}::{name}
        parts = source_id.split('::', 3)
        next unless parts.length >= 3

        file = parts[0]
        item_kind = parts[1]
        name = parts[2]
        scope = item_kind == 'test' || test_file_for_language?(language, file) ? 'test' : 'source'

        items << Item.new(
          id: source_id,
          kind: kind,
          scope: scope,
          file: file,
          name: name
        )
      end
      unless reported_parsers == Set.new(['tree-sitter'])
        reported = reported_parsers.to_a.sort.join(', ')
        raise RuntimeError, "Crystal discovery did not report tree-sitter (reported: #{reported.empty? ? 'none' : reported})"
      end
      [items, 'chiasmus-tree-sitter', command.join(' ')]
    rescue => e
      raise unless fallback

      warn "Crystal discovery failed: #{e.message}; falling back to regex"
      [discover_with_regex(base, language), 'regex', nil]
    end
  end

  def discover_crystal_binary(root_dir = nil)
    crystal_discovery_candidates(root_dir).find { |path| File.executable?(path) } ||
      crystal_discovery_source_fallback(root_dir)
  end

  # True when a tree-sitter grammar for `language` is discoverable via
  # CHIASMUS_GRAMMAR_DIR, the bundled grammars next to the discovery binary,
  # or a repo-local ./grammars directory. This is what makes any grammar-backed
  # language work without editing the supported-language lists.
  def grammar_available?(language, root_dir = nil)
    grammar_dirs(root_dir).any? do |dir|
      File.directory?(File.join(dir, "tree-sitter-#{language}"))
    end
  end

  def grammar_dirs(root_dir = nil)
    dirs = []
    if (env = ENV['CHIASMUS_GRAMMAR_DIR']) && !env.empty?
      dirs << env
    end
    if (bin = discover_crystal_binary(root_dir))
      dirs << File.join(File.dirname(bin), 'grammars')
    end
    dirs << File.join(root_dir.to_s, 'grammars') if root_dir
    dirs.uniq
  end

  def crystal_discovery_candidates(root_dir = nil)
    candidates = []

    env_override = ENV['CHIASMUS_DISCOVER_BIN']
    candidates << env_override if env_override && !env_override.strip.empty?

    script_root = File.expand_path('..', __dir__)
    skill_bin = File.join(script_root, 'bin')
    executable_names = windows? ? %w[chiasmus-discover.exe chiasmus_discover.exe] : %w[chiasmus-discover chiasmus_discover]

    platform_dir = bundled_platform_dir(script_root)
    executable_names.each do |name|
      candidates << File.join(platform_dir, name)
      candidates << File.join(skill_bin, name)
    end

    if root_dir
      executable_names.each do |name|
        candidates << File.join(root_dir, 'bin', name)
      end
    end

    candidates.uniq
  end

  def crystal_discovery_source_fallback(root_dir = nil)
    candidates = []
    candidates << File.join(root_dir, 'src', 'chiasmus_discover.cr') if root_dir
    candidates << File.join(__dir__, '..', 'src', 'chiasmus_discover.cr')

    src = candidates.find { |path| File.exist?(path) }
    ['crystal', 'run', src, '--'] if src
  end

  def bundled_platform_dir(script_root)
    File.join(script_root, 'bin', platform_key)
  end

  def platform_key
    host_os = RbConfig::CONFIG['host_os']
    host_cpu = RbConfig::CONFIG['host_cpu']

    os = case host_os
         when /darwin/i then 'darwin'
         when /linux/i then 'linux'
         when /mswin|mingw|cygwin/i then 'windows'
         else
           host_os.downcase.gsub(/[^a-z0-9]+/, '-')
         end

    cpu = case host_cpu
          when /arm64|aarch64/i then 'aarch64'
          when /x86_64|amd64/i then 'x86_64'
          else
            host_cpu.downcase.gsub(/[^a-z0-9]+/, '-')
          end

    "#{os}-#{cpu}"
  end

  def windows?
    RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/i
  end

  def discover_items(root_dir:, source_path:, language:, parser_mode: 'auto', include_paths: [], exclude_patterns: [])
    base = resolve_base(root_dir, source_path)
    raise ArgumentError, "Source directory does not exist: #{base}" unless base.directory?

    unless grammar_available?(language, root_dir) || SUPPORTED_LANGUAGES.include?(language)
      raise ArgumentError, "Unsupported language: #{language} (no tree-sitter grammar and no regex extractor)"
    end

    parser = effective_parser(language, parser_mode, root_dir)
    if parser_mode == 'tree-sitter' && parser != 'tree-sitter'
      raise RuntimeError, "tree-sitter parser unavailable for #{language}; install chiasmus-discover or use --parser regex"
    end

    items, backend, discover_bin = if parser == 'tree-sitter'
                                      discover_with_crystal_discovery(base, language, root_dir: root_dir, fallback: parser_mode != 'tree-sitter')
                                    else
                                      [discover_with_regex(base, language), 'regex', nil]
                                    end
    warn "PARITY_DISCOVERY_BACKEND=#{backend}"
    warn "PARITY_DISCOVERY_BINARY=#{discover_bin}" if discover_bin

    filtered_items = filter_scope_items(
      dedupe_items(items),
      include_paths: include_paths,
      exclude_patterns: exclude_patterns
    )
    @last_discovery_report = {
      'base' => base.to_s,
      'parser_requested' => parser_mode,
      'backend' => backend,
      'binary' => discover_bin,
      'include_paths' => normalized_scope_values(include_paths, '.'),
      'exclude_patterns' => normalized_scope_values(exclude_patterns, nil),
    }
    warn "PARITY_DISCOVERY_SCOPE=#{JSON.generate(@last_discovery_report.slice('include_paths', 'exclude_patterns'))}"

    [base, filtered_items]
  end

  def last_discovery_report
    @last_discovery_report || {}
  end

  def write_discovery_metadata(manifest_path)
    File.write("#{manifest_path}.metadata.json", JSON.pretty_generate(last_discovery_report) + "\n")
  end

  def filter_scope_items(items, include_paths:, exclude_patterns:)
    includes = normalized_scope_values(include_paths, '.')
    excludes = normalized_scope_values(exclude_patterns, nil)
    items.select do |item|
      file = item.file.tr('\\', '/')
      included = includes.any? { |path| path == '.' || file == path || file.start_with?("#{path}/") }
      excluded = excludes.any? { |pattern| File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_EXTGLOB) }
      included && !excluded
    end
  end

  def normalized_scope_values(values, default)
    values = Array(values).flat_map { |value| value.to_s.split(',') }
                  .map { |value| value.strip.tr('\\', '/').sub(%r{\A\./}, '').sub(%r{/\z}, '') }
                  .reject(&:empty?)
    values = [default] if values.empty? && default
    values.uniq.sort
  end

  def effective_parser(language, parser_mode, root_dir = nil)
    mode = parser_mode.to_s
    treesitter_available = grammar_available?(language, root_dir)
    return 'regex' if mode.empty? || mode == 'regex'
    return treesitter_available ? 'tree-sitter' : 'regex' if mode == 'tree-sitter'
    return treesitter_available ? 'tree-sitter' : 'regex' if mode == 'auto'

    raise ArgumentError, "Invalid parser mode: #{parser_mode} (expected auto|regex|tree-sitter)"
  end

  def dedupe_items(items)
    seen = Set.new
    items.select do |item|
      key = [item.id, item.kind, item.scope]
      next false if seen.include?(key)

      seen << key
      true
    end.sort_by(&:id)
  end

  def kind_from_id(id)
    parts = id.to_s.split('::', 3)
    return nil unless parts.length >= 3

    parts[1]
  end

  def curated_inventory_items(items, language:)
    allowed = CURATED_KINDS.fetch(language, DEFAULT_CURATED_KINDS)

    dedupe_items(items.select { |item| allowed.include?(item.kind) })
  end

  def manifest_kinds(path)
    kinds = Set.new
    load_manifest_rows(path, min_cols: 1).each do |cols|
      kind = kind_from_id(cols[0])
      kinds << kind if kind
    end
    kinds
  end

  def filter_items_for_manifest(items, manifest_path:, language:)
    tracked_kinds = manifest_kinds(manifest_path)
    tracked_kinds = CURATED_KINDS.fetch(language, DEFAULT_CURATED_KINDS) if tracked_kinds.empty?
    dedupe_items(items.select { |item| tracked_kinds.include?(item.kind) })
  end

  def discover_with_regex(base, language)
    entries = files_for_language(base, language)
    source_items = []
    test_items = []

    entries.each do |path, rel|
      content = read_utf8_text(path)
      src, test = case language
                  when 'go' then extract_go(rel, content)
                  when 'rust' then extract_rust(rel, content)
                  when 'crystal' then extract_crystal(rel, content)
                  when 'java' then extract_java(rel, content)
                  when 'ruby' then extract_ruby(rel, content)
                  when 'typescript' then extract_typescript(rel, content)
                  when 'python' then extract_python(rel, content)
                  else [[], []]
                  end
      source_items.concat(src) unless test_file_for_language?(language, rel)
      test_items.concat(test)
    end

    source_items + test_items
  end

  def files_for_language(base, language)
    files = Dir.glob('**/*', File::FNM_DOTMATCH, base: base.to_s)
               .reject { |f| f.start_with?('.') || f.include?('/.git/') || f.end_with?('/.git') }

    selected = files.select do |rel|
      full = base + rel
      next false unless full.file?

      case language
      when 'go'
        rel.end_with?('.go')
      when 'rust'
        rel.end_with?('.rs')
      when 'crystal'
        rel.end_with?('.cr')
      when 'java'
        rel.end_with?('.java')
      when 'ruby'
        rel.end_with?('.rb')
      when 'typescript'
        rel.end_with?('.ts', '.js')
      when 'python'
        rel.end_with?('.py')
      else
        false
      end
    end

    selected.sort.map { |rel| [(base + rel).to_s, rel] }
  end

  def emit_source(rel, kind, name)
    Item.new(id: "#{rel}::#{kind}::#{name}", kind: kind, scope: 'source', file: rel, name: name)
  end

  def emit_test(rel, name)
    Item.new(id: "#{rel}::test::#{name}", kind: 'test', scope: 'test', file: rel, name: name)
  end

  def test_file_for_language?(language, rel)
    case language
    when 'go'
      rel.end_with?('_test.go')
    when 'rust'
      rel.end_with?('_test.rs') || rel.start_with?('test/', 'tests/') || rel.include?('/test/') || rel.include?('/tests/')
    when 'crystal'
      rel.end_with?('_spec.cr') || rel.start_with?('spec/')
    when 'java'
      rel.include?('/test/') || rel.end_with?('Test.java')
    when 'ruby'
      rel.end_with?('_spec.rb', '_test.rb') || rel.start_with?('spec/') || rel.start_with?('test/')
    when 'typescript'
      rel.end_with?('.test.ts', '.spec.ts', '.test.js', '.spec.js') || rel.include?('/test/') || rel.include?('/tests/')
    when 'python'
      rel.end_with?('_test.py') || rel.match?(/test_.*\.py\z/) || rel.include?('/test/') || rel.include?('/tests/')
    else
      rel.include?('/test/') || rel.include?('/tests/') || rel.include?('/spec/') || rel.match?(/_test\b|_spec\b/)
    end
  end

  def extract_go(rel, text)
    source = []
    tests = []

    in_const_block = false

    text.each_line do |line|
      stripped = line.strip

      if stripped.match?(/^const\s*\(/)
        in_const_block = true
        next
      end

      if in_const_block
        if stripped == ')'
          in_const_block = false
        elsif (m = stripped.match(/^([A-Z][A-Za-z0-9_]*)\b/))
          source << emit_source(rel, 'const', m[1])
        end
        next
      end

      if (m = stripped.match(/^const\s+([A-Z][A-Za-z0-9_]*)\b/))
        source << emit_source(rel, 'const', m[1])
      end

      if (m = stripped.match(/^type\s+([A-Z][A-Za-z0-9_]*)\b/))
        kind = stripped.include?(' struct') || stripped.end_with?('struct{') || stripped.end_with?('struct {') ? 'struct' : 'type'
        source << emit_source(rel, kind, m[1])
      end

      if (m = stripped.match(/^func\s+([A-Z][A-Za-z0-9_]*)\s*\(/))
        source << emit_source(rel, 'func', m[1])
      end

      if (m = stripped.match(/^func\s+\(([^)]+)\)\s+([A-Z][A-Za-z0-9_]*)\s*\(/))
        recv = m[1].split.last.to_s.delete('*')
        source << emit_source(rel, 'method', "#{recv}.#{m[2]}") unless recv.empty?
      end

      if (m = stripped.match(/^func\s+(Test[A-Za-z0-9_]*)\s*\(/))
        tests << emit_test(rel, m[1])
      end
    end

    [source, tests]
  end

  def extract_rust(rel, text)
    source = []
    tests = []

    pub_impl = nil
    pending_test_attr = false

    text.each_line do |line|
      stripped = line.strip

      if (m = stripped.match(/^pub\s+const\s+([A-Z][A-Za-z0-9_]*)\b/))
        source << emit_source(rel, 'const', m[1])
      end
      if (m = stripped.match(/^pub\s+struct\s+([A-Z][A-Za-z0-9_]*)\b/))
        source << emit_source(rel, 'struct', m[1])
      end
      if (m = stripped.match(/^pub\s+enum\s+([A-Z][A-Za-z0-9_]*)\b/))
        source << emit_source(rel, 'enum', m[1])
      end
      if (m = stripped.match(/^pub\s+trait\s+([A-Z][A-Za-z0-9_]*)\b/))
        source << emit_source(rel, 'trait', m[1])
      end
      if (m = stripped.match(/^pub\s+type\s+([A-Z][A-Za-z0-9_]*)\b/))
        source << emit_source(rel, 'type', m[1])
      end
      if (m = stripped.match(/^pub\s+fn\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\(/))
        source << emit_source(rel, 'func', m[1])
      end

      if (m = stripped.match(/^impl(?:<[^>]+>)?\s+([A-Z][A-Za-z0-9_:]*)/))
        pub_impl = m[1]
      elsif stripped.start_with?('}')
        pub_impl = nil
      elsif pub_impl && (m = stripped.match(/^pub\s+fn\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\(/))
        source << emit_source(rel, 'method', "#{pub_impl}.#{m[1]}")
      end

      pending_test_attr = true if stripped.start_with?('#[test]')
      if pending_test_attr && (m = stripped.match(/^fn\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\(/))
        tests << emit_test(rel, m[1])
        pending_test_attr = false
      end
    end

    [source, tests]
  end

  def extract_crystal(rel, text)
    source = []
    tests = []

    namespace = []

    text.each_line do |line|
      stripped = line.strip

      if (m = stripped.match(/^(class|module|struct|enum)\s+([A-Z][A-Za-z0-9_:]*)/))
        kind = m[1]
        name = m[2]
        source << emit_source(rel, kind, name)
        namespace << name
        next
      end

      if stripped == 'end'
        namespace.pop unless namespace.empty?
        next
      end

      if (m = stripped.match(/^([A-Z][A-Z0-9_]*)\s*=/))
        source << emit_source(rel, 'const', m[1])
      end

      if (m = stripped.match(/^def\s+(self\.)?([a-z_][A-Za-z0-9_!?=]*)\b/))
        recv = namespace.last
        name = m[2]
        kind = m[1] ? 'func' : 'method'
        id_name = recv ? "#{recv}.#{name}" : name
        source << emit_source(rel, kind, id_name)
      end

      if (m = stripped.match(/^it\s+"([^"]+)"/))
        tests << emit_test(rel, m[1])
      end
    end

    if rel.end_with?('_spec.cr')
      text.each_line do |line|
        stripped = line.strip
        if (m = stripped.match(/^describe\s+([A-Za-z0-9_:"'. ]+)/))
          tests << emit_test(rel, m[1])
        end
      end
    end

    [source, tests]
  end

  def extract_java(rel, text)
    source = []
    tests = []

    current_type = nil
    pending_test_attr = false

    text.each_line do |line|
      stripped = line.strip

      if (m = stripped.match(/^public\s+(class|interface|enum|record)\s+([A-Z][A-Za-z0-9_]*)\b/))
        source << emit_source(rel, m[1], m[2])
        current_type = m[2]
      end

      if (m = stripped.match(/^public\s+static\s+final\s+[A-Za-z0-9_<>, ?\[\]]+\s+([A-Z][A-Z0-9_]*)\b/))
        source << emit_source(rel, 'const', m[1])
      end

      if (m = stripped.match(/^public\s+(?:static\s+)?[A-Za-z0-9_<>, ?\[\]]+\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\(/))
        next if %w[if for while switch catch].include?(m[1])

        source << if current_type && m[1] == current_type
                    emit_source(rel, 'ctor', "#{current_type}.#{m[1]}")
                  elsif current_type
                    emit_source(rel, 'method', "#{current_type}.#{m[1]}")
                  else
                    emit_source(rel, 'func', m[1])
                  end
      end

      pending_test_attr = true if stripped == '@Test'
      if pending_test_attr && (m = stripped.match(/^(public\s+)?void\s+([a-zA-Z_][A-Za-z0-9_]*)\s*\(/))
        tests << emit_test(rel, m[2])
        pending_test_attr = false
      end
    end

    [source, tests]
  end

  def extract_ruby(rel, text)
    source = []
    tests = []

    namespace = []

    text.each_line do |line|
      stripped = line.strip

      if (m = stripped.match(/^(class|module)\s+([A-Z][A-Za-z0-9_:]*)/))
        source << emit_source(rel, m[1], m[2])
        namespace << m[2]
        next
      end

      if stripped == 'end'
        namespace.pop unless namespace.empty?
        next
      end

      if (m = stripped.match(/^([A-Z][A-Z0-9_]*)\s*=/))
        source << emit_source(rel, 'const', m[1])
      end

      if (m = stripped.match(/^def\s+(self\.)?([a-z_][A-Za-z0-9_!?=]*)/))
        recv = namespace.last
        name = m[2]
        kind = m[1] ? 'func' : 'method'
        source << emit_source(rel, kind, recv ? "#{recv}.#{name}" : name)
      end

      if (m = stripped.match(/^def\s+(test_[A-Za-z0-9_]+)/))
        tests << emit_test(rel, m[1])
      end
      if (m = stripped.match(/^it\s+["'](.+?)["']/))
        tests << emit_test(rel, m[1])
      end
      if (m = stripped.match(/^test\s+["'](.+?)["']/))
        tests << emit_test(rel, m[1])
      end
    end

    [source, tests]
  end

  def extract_typescript(rel, text)
    source = []
    tests = []

    namespace = []
    in_interface = false
    in_type_alias = false

    text.each_line do |line|
      stripped = line.strip

      # Handle export keyword
      stripped = stripped.sub('export ', '').strip if stripped.start_with?('export ')

      # Class definitions
      if (m = stripped.match(/^(abstract\s+)?class\s+([A-Z][A-Za-z0-9_$]*)/))
        source << emit_source(rel, 'class', m[2])
        namespace << m[2]
        next
      end

      # Interface definitions
      if (m = stripped.match(/^interface\s+([A-Z][A-Za-z0-9_$]*)/))
        source << emit_source(rel, 'interface', m[1])
        in_interface = true
        next
      end

      # Type alias definitions
      if (m = stripped.match(/^type\s+([A-Z][A-Za-z0-9_$]*)\s*=/))
        source << emit_source(rel, 'type', m[1])
        in_type_alias = true
        next
      end

      # Function definitions
      if (m = stripped.match(/^function\s+([a-z_][A-Za-z0-9_$]*)/))
        source << emit_source(rel, 'function', m[1])
        next
      end

      # Method definitions in classes
      # Check if this looks like a method (not a function call)
      if (m = stripped.match(/^([a-z_][A-Za-z0-9_$]*)\s*\(/)) && !namespace.empty? && !stripped.start_with?('if ', 'for ',
                                                                                                            'while ', 'switch ', 'return ', 'throw ')
        source << emit_source(rel, 'method', "#{namespace.last}.#{m[1]}")
      end

      # Arrow functions (const/let/var assignments)
      if (m = stripped.match(/^(const|let|var)\s+([a-z_][A-Za-z0-9_$]*)\s*=\s*(async\s*)?\(/))
        source << emit_source(rel, 'function', m[2])
      end

      # Constant declarations
      if (m = stripped.match(/^(const|let|var)\s+([A-Z][A-Z0-9_$]*)\s*=/))
        source << emit_source(rel, 'const', m[2])
      end

      # Test functions (describe, it, test)
      if (m = stripped.match(/^describe\s*\(\s*["'](.+?)["']/))
        tests << emit_test(rel, m[1])
      end
      if (m = stripped.match(/^it\s*\(\s*["'](.+?)["']/))
        tests << emit_test(rel, m[1])
      end
      if (m = stripped.match(/^test\s*\(\s*["'](.+?)["']/))
        tests << emit_test(rel, m[1])
      end

      # End of interface or type alias
      if stripped == '}' && (in_interface || in_type_alias)
        in_interface = false
        in_type_alias = false
      end

      # End of class
      namespace.pop if stripped == '}' && !namespace.empty?
    end

    [source, tests]
  end

  # Low-fidelity regex fallback for Python (tree-sitter is preferred).
  def extract_python(rel, text)
    source = []
    tests = []

    current_class = nil

    text.each_line do |line|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?('#')

      if (m = stripped.match(/\Aclass\s+([A-Za-z_]\w*)\s*(?:\([^)]*\))?\s*:/))
        current_class = m[1]
        source << emit_source(rel, 'class', m[1])
        next
      end

      if (m = stripped.match(/\Adef\s+([A-Za-z_]\w*)\s*\(/))
        name = m[1]
        if name.start_with?('test_') || rel.include?('test')
          tests << emit_test(rel, name)
        elsif current_class
          source << emit_source(rel, 'method', "#{current_class}.#{name}")
        else
          source << emit_source(rel, 'function', name)
        end
        next
      end

      if (m = stripped.match(/\A([A-Z][A-Z0-9_]*)\s*=\s*(?:[^=].*)?\z/))
        source << emit_source(rel, 'const', m[1])
      end
    end

    [source, tests]
  end

  def write_inventory(path, items)
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, 'w') do |f|
      f.puts "# source_id\tkind\tstatus\tcrystal_refs\tnotes"
      items.each do |item|
        f.puts "#{item.id}\t#{item.kind}\tmissing\t-\tauto-generated"
      end
    end
  end

  def write_scope_manifest(path, items, scope:, header_id:, notes_overrides: {})
    FileUtils.mkdir_p(File.dirname(path))
    File.open(path, 'w') do |f|
      f.puts "# #{header_id}\tstatus\tcrystal_refs\tnotes"
      items.select { |item| item.scope == scope }
           .sort_by(&:id)
           .each do |item|
        notes = notes_overrides[item.id] || 'baseline'
        f.puts "#{item.id}\tmissing\t-\t#{notes}"
      end
    end
  end

  def load_notes_overrides(path)
    return {} unless path && File.file?(path)

    overrides = {}
    read_utf8_lines(path, chomp: true).each_with_index do |line, idx|
      next if line.start_with?('#') || line.strip.empty?

      cols = line.split("\t", -1)
      if cols.length < 2
        raise "Malformed notes override row #{idx + 1} in #{path}: expected 2 columns (source_api_id\\tnotes)"
      end

      source_id = cols[0].to_s.strip
      note = cols[1].to_s.strip
      next if source_id.empty?

      overrides[source_id] = note.empty? ? '-' : note
    end
    overrides
  end

  def load_manifest_rows(path, min_cols:)
    rows = []
    read_utf8_lines(path, chomp: true).each_with_index do |line, idx|
      next if line.start_with?('#') || line.strip.empty?

      cols = line.split("\t", -1)
      raise "Malformed manifest row #{idx + 1} in #{path}: expected >= #{min_cols} columns" if cols.length < min_cols

      rows << cols
    end
    rows
  end

  def read_utf8_text(path)
    File.binread(path).force_encoding(Encoding::UTF_8).scrub
  end

  def read_utf8_lines(path, chomp: false)
    read_utf8_text(path).lines(chomp: chomp)
  end
end
