#!/usr/bin/env bash
# Cross-language reconciliation driver for the parity skill.
#
# Drives: source facts -> target facts -> maps / surfaces / maps-prolog /
# divergences (when a ledger exists). Wraps `chiasmus-facts` + `chiasmus-parity`.
#
# Usage:
#   reconcile_parity.sh <repo-root> <source-path> <source-language> <target-dir> [rules-file]
#
# rules-file defaults to <repo-root>/plans/parity_rules.yml (or $PORT_MAP_RULES)
# when omitted; a missing file is skipped with a warning.
#
# Example (Java -> Crystal):
#   reconcile_parity.sh . vendor/pdfbox java src plans/parity_rules.yml
#
# Environment overrides:
#   CHIASMUS_TOOLCHAIN_DIR                   complete verified toolchain
#   PORT_MAP_RULES                           default rules file
#   PORT_RECONCILE_OUT                       output directory
#   PORT_INVENTORY                           curated ledger path
#   PORT_SCOPE_EXCLUDE                       comma-separated paths/globs to skip (passed to chiasmus-facts --exclude)
#   PORT_RECONCILE_CACHE_DIR                 persistent shared Chiasmus extraction cache
set -euo pipefail

ROOT_DIR="${1:?usage: reconcile_parity.sh <repo-root> <source-path> <source-language> <target-dir> [rules-file]}"
SOURCE_PATH="${2:?source path required}"
SOURCE_LANGUAGE="${3:?source language required}"
TARGET_DIR="${4:?target dir required}"
RULES_FILE="${5:-${PORT_MAP_RULES:-${ROOT_DIR}/plans/parity_rules.yml}}"

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${PORT_RECONCILE_OUT:-${ROOT_DIR}/plans/generated/parity/${SOURCE_LANGUAGE}}"
LEDGER="${PORT_INVENTORY:-${ROOT_DIR}/plans/inventory/${SOURCE_LANGUAGE}_port_inventory.tsv}"

resolve_path() {
  local value="$1"
  if [[ "${value}" = /* ]]; then printf '%s\n' "${value}"; else printf '%s\n' "${ROOT_DIR}/${value}"; fi
}

TOOLCHAIN="$(python3 "${SCRIPT_DIR}/resolve_toolchain.py" --require-capability facts.typed-declarations --require-capability parity.bundle)"
FACTS_BIN="${TOOLCHAIN}/chiasmus-facts"
PARITY_BIN="${TOOLCHAIN}/chiasmus-parity"
export CHIASMUS_GRAMMAR_DIR="${TOOLCHAIN}/grammars"
CACHE_DIR="${PORT_RECONCILE_CACHE_DIR:-${CHIASMUS_CACHE_DIR:-${XDG_CACHE_HOME:-${HOME}/.cache}/chiasmus}}"
PARITY_HELP="$("${PARITY_BIN}" --help 2>&1)"
FACTS_HELP="$("${FACTS_BIN}" --help 2>&1)"
if [[ "${PARITY_HELP}" != *"maps-prolog"* || "${PARITY_HELP}" != *"surfaces"* ]]; then
  echo "${PARITY_BIN} lacks reconciliation formats; install a compatible complete Chiasmus release." >&2
  exit 1
fi
if [[ "${FACTS_HELP}" != *"--cache-dir"* ]]; then
  echo "${FACTS_BIN} lacks the persistent cache option; install a compatible complete Chiasmus release." >&2
  exit 1
fi

EXCLUDE_ARGS=()
if [[ -n "${PORT_SCOPE_EXCLUDE:-}" ]]; then
  IFS=',' read -ra _excludes <<< "${PORT_SCOPE_EXCLUDE}"
  for pattern in "${_excludes[@]}"; do
    pattern="$(printf '%s' "${pattern}" | sed 's/^ *//;s/ *$//')"
    [[ -n "${pattern}" ]] && EXCLUDE_ARGS+=(--exclude "${pattern}")
  done
fi

SOURCE_DIR="$(resolve_path "${SOURCE_PATH}")"
TARGET_ABS="$(resolve_path "${TARGET_DIR}")"
[[ -d "${SOURCE_DIR}" ]] || { echo "source dir not found: ${SOURCE_DIR}" >&2; exit 1; }
[[ -d "${TARGET_ABS}" ]] || { echo "target dir not found: ${TARGET_ABS}" >&2; exit 1; }

mkdir -p "${OUT_DIR}"
SOURCE_FACTS="${OUT_DIR}/source_facts.pl"
TARGET_FACTS="${OUT_DIR}/target_facts.pl"
SOURCE_DECLARATIONS="${OUT_DIR}/source-declarations.jsonl"
TARGET_DECLARATIONS="${OUT_DIR}/target-declarations.jsonl"
TYPED_SIDECARS=false
case "${SOURCE_LANGUAGE}" in
  java|go|crystal|rust)
    if [[ "${FACTS_HELP}" != *"--declarations-out"* ||
          "${PARITY_HELP}" != *"--source-declarations"* ||
          "${PARITY_HELP}" != *"--target-declarations"* ||
          "${PARITY_HELP}" != *"--bundle-dir"* ]]; then
      echo "Verified toolchain advertises typed reconciliation but its CLI flags are missing." >&2
      exit 1
    fi
    TYPED_SIDECARS=true ;;
esac

SOURCE_FACT_ARGS=()
TARGET_FACT_ARGS=()
if [[ "${TYPED_SIDECARS}" == true ]]; then
  SOURCE_FACT_ARGS+=(--declarations-out "${SOURCE_DECLARATIONS}")
  TARGET_FACT_ARGS+=(--declarations-out "${TARGET_DECLARATIONS}")
else
  echo "Typed declaration sidecars unavailable for this language/toolchain; using legacy reconciliation." >&2
fi

echo "Extracting ${SOURCE_LANGUAGE} facts: ${SOURCE_DIR}"
"${FACTS_BIN}" --language "${SOURCE_LANGUAGE}" --dir "${SOURCE_DIR}" --cache-dir "${CACHE_DIR}" ${EXCLUDE_ARGS[@]+"${EXCLUDE_ARGS[@]}"} ${SOURCE_FACT_ARGS[@]+"${SOURCE_FACT_ARGS[@]}"} > "${SOURCE_FACTS}"
echo "Extracting crystal facts: ${TARGET_ABS}"
"${FACTS_BIN}" --language crystal --dir "${TARGET_ABS}" --cache-dir "${CACHE_DIR}" ${EXCLUDE_ARGS[@]+"${EXCLUDE_ARGS[@]}"} ${TARGET_FACT_ARGS[@]+"${TARGET_FACT_ARGS[@]}"} > "${TARGET_FACTS}"

PARITY_ARGS=(--source-facts "${SOURCE_FACTS}" --crystal-facts "${TARGET_FACTS}")
if [[ "${TYPED_SIDECARS}" == true ]]; then
  PARITY_ARGS+=(--source-declarations "${SOURCE_DECLARATIONS}" --target-declarations "${TARGET_DECLARATIONS}")
fi
RULES_PATH="$(resolve_path "${RULES_FILE}")"
if [[ -f "${RULES_PATH}" ]]; then
  PARITY_ARGS+=(--map-rules "${RULES_PATH}")
  echo "Using rules: ${RULES_PATH}"
else
  echo "No rules file at ${RULES_PATH}; proceeding without map rules." >&2
fi

if [[ -f "${LEDGER}" ]]; then
  PARITY_ARGS+=(--inventory "${LEDGER}")
else
  echo "No ledger at ${LEDGER}; skipping divergence join."
fi

if [[ "${PARITY_HELP}" == *"--bundle-dir"* ]]; then
  echo "Reconciling maps, surfaces, and Prolog in one run..."
  if [[ "${PARITY_HELP}" == *"--cache-dir"* ]]; then
    PARITY_ARGS+=(--cache-dir "${CACHE_DIR}")
  fi
  "${PARITY_BIN}" "${PARITY_ARGS[@]}" --bundle-dir "${OUT_DIR}"
else
  echo "Bundle mode unavailable; using compatible report invocations..."
  "${PARITY_BIN}" "${PARITY_ARGS[@]}" --format maps > "${OUT_DIR}/maps.tsv"
  "${PARITY_BIN}" "${PARITY_ARGS[@]}" --format surfaces > "${OUT_DIR}/surfaces.tsv"
  "${PARITY_BIN}" "${PARITY_ARGS[@]}" --format maps-prolog > "${OUT_DIR}/maps.pl"
  if [[ -f "${LEDGER}" ]]; then
    "${PARITY_BIN}" "${PARITY_ARGS[@]}" --format divergences > "${OUT_DIR}/divergences.tsv"
  fi
fi

echo "Reconciliation bundle written to ${OUT_DIR}"
