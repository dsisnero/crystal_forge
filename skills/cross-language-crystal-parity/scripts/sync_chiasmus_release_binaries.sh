#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <tag> [owner/repo]" >&2
  echo "Example: $0 v0.2.0 dsisnero/chiasmus.cr" >&2
  exit 1
fi

TAG="$1"
REPO="${2:-dsisnero/chiasmus.cr}"
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BIN_ROOT="${SKILL_DIR}/bin"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

download_and_unpack() {
  local asset_name="$1"
  local platform_dir="$2"
  local archive_path="${TMP_DIR}/${asset_name}"
  local extract_dir="${TMP_DIR}/${platform_dir}"
  local url="https://github.com/${REPO}/releases/download/${TAG}/${asset_name}"

  mkdir -p "${extract_dir}" "${BIN_ROOT}/${platform_dir}"
  echo "Fetching ${url}"
  curl -fsSL "${url}" -o "${archive_path}"

  case "${asset_name}" in
    *.tar.gz) tar -xzf "${archive_path}" -C "${extract_dir}" ;;
    *.zip) unzip -q "${archive_path}" -d "${extract_dir}" ;;
    *) echo "Unsupported archive: ${asset_name}" >&2; exit 1 ;;
  esac

  local package_root="${extract_dir}/chiasmus"
  if [[ ! -d "${package_root}" ]]; then
    echo "Expected package root ${package_root} not found" >&2
    exit 1
  fi

  cp "${package_root}/chiasmus-discover"* "${BIN_ROOT}/${platform_dir}/"
  cp "${package_root}/chiasmus-parity"* "${BIN_ROOT}/${platform_dir}/"

  rm -rf "${BIN_ROOT:?}/${platform_dir}/grammars"
  cp -R "${package_root}/grammars" "${BIN_ROOT}/${platform_dir}/grammars"
}

download_and_unpack "chiasmus-Linux-x86_64-${TAG}.tar.gz" "linux-x86_64"
download_and_unpack "chiasmus-macOS-aarch64-${TAG}.tar.gz" "darwin-aarch64"
download_and_unpack "chiasmus-Windows-x86_64-${TAG}.zip" "windows-x86_64"

echo "Synced chiasmus-discover/chiasmus-parity and grammars into ${BIN_ROOT}"
