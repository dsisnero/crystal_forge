#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(pwd)}"

failures=0

pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; failures=$((failures + 1)); }

require_file() {
  local path="$1"
  local label="$2"
  if [[ -f "$path" ]]; then
    pass "$label exists ($path)"
  else
    fail "$label missing ($path)"
  fi
}

require_dir() {
  local path="$1"
  local label="$2"
  if [[ -d "$path" ]]; then
    pass "$label exists ($path)"
  else
    fail "$label missing ($path)"
  fi
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if [[ -f "$file" ]] && rg -n --pcre2 "$pattern" "$file" >/dev/null 2>&1; then
    pass "$label"
  else
    fail "$label"
  fi
}

echo "Verifying initialized Crystal port baseline in: ${ROOT_DIR}"

# Makefile + required targets
MAKEFILE="${ROOT_DIR}/Makefile"
require_file "$MAKEFILE" "Makefile"
for target in install update format lint test clean; do
  require_pattern "$MAKEFILE" "^${target}:" "Makefile target '${target}' present"
done

# Ameba config
AMEBA="${ROOT_DIR}/.ameba.yml"
require_file "$AMEBA" ".ameba.yml"
require_pattern "$AMEBA" '^Version:\s*"?.+"?$' ".ameba.yml has Version"
require_pattern "$AMEBA" '^Excluded:' ".ameba.yml has Excluded block"
for path in 'lib/\*\*/\*' 'temp/\*\*/\*' 'vendor/\*\*/\*'; do
  require_pattern "$AMEBA" "${path}" ".ameba.yml excludes ${path}"
done

# rumdl config (.rumdl.toml preferred)
RUMDL_TOML="${ROOT_DIR}/.rumdl.toml"
RUMDL_ALT="${ROOT_DIR}/.rumdl"
if [[ -f "$RUMDL_TOML" ]]; then
  pass ".rumdl.toml exists"
  RUMDL_FILE="$RUMDL_TOML"
elif [[ -f "$RUMDL_ALT" ]]; then
  pass ".rumdl exists"
  RUMDL_FILE="$RUMDL_ALT"
else
  fail ".rumdl.toml (or .rumdl) missing"
  RUMDL_FILE=""
fi

if [[ -n "$RUMDL_FILE" ]]; then
  require_pattern "$RUMDL_FILE" '^\[global\]' "rumdl has [global] section"
  require_pattern "$RUMDL_FILE" '^exclude\s*=\s*\[' "rumdl has exclude list"
  require_pattern "$RUMDL_FILE" '"temp"' "rumdl excludes temp"
  require_pattern "$RUMDL_FILE" '"vendor"' "rumdl excludes vendor"
fi

# docs baseline
DOCS_DIR="${ROOT_DIR}/docs"
require_dir "$DOCS_DIR" "docs directory"
for doc in architecture.md development.md coding-guidelines.md testing.md pr-workflow.md; do
  f="$DOCS_DIR/$doc"
  require_file "$f" "docs/$doc"
  require_pattern "$f" '^#\s+.+$' "docs/$doc has top-level heading"
done

# .gitignore baseline
GITIGNORE="${ROOT_DIR}/.gitignore"
require_file "$GITIGNORE" ".gitignore"
require_pattern "$GITIGNORE" '(^|/)\.crystal-cache/$|^\.crystal-cache/$' ".gitignore ignores .crystal-cache/"
if [[ -f "$GITIGNORE" ]] && rg -n --pcre2 '^(\/)?docs\/$' "$GITIGNORE" >/dev/null 2>&1; then
  fail ".gitignore must not ignore docs/ (required baseline docs must be committed)"
else
  pass ".gitignore does not ignore docs/"
fi

# README baseline elements
README="${ROOT_DIR}/README.md"
require_file "$README" "README.md"
require_pattern "$README" '(?i)crystal\s+port\s+of\s+https?://' "README includes 'Crystal port of <upstream-url>' attribution"
require_pattern "$README" 'https?://|github\.com' "README contains source attribution URL"
require_pattern "$README" '(?im)^##\s+Upstream README Highlights\s*$' "README includes 'Upstream README Highlights' section"
require_pattern "$README" '(?i)submodule\s+README|upstream\s+README' "README references merged upstream/submodule README context"

if [[ "$failures" -eq 0 ]]; then
  echo "Baseline verification passed."
  exit 0
fi

echo "Baseline verification failed with ${failures} issue(s)."
exit 1
