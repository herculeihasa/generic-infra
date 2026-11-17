#!/usr/bin/env bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# Shared helpers for the CI scripts (sourced). Work identically on GitHub
# Actions runners and on a developer machine / WSL: GitHub-specific features
# (log groups, annotations, step summary, PATH) are used only when present.
# -----------------------------------------------------------------------------
set -Eeuo pipefail

# cd + pwd normalises to a POSIX path (Git for Windows returns "E:/...").
CI_REPO_ROOT="$(cd "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)" && pwd)"
CI_TOOLS_DIR="${CI_TOOLS_DIR:-${HOME}/.cache/azure-infra-ci}"
CI_BIN_DIR="${CI_TOOLS_DIR}/bin"
export PATH="${CI_BIN_DIR}:${PATH}"

ci_log() { printf '[ci] %s\n' "$*" >&2; }
ci_warn() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::warning::$*"; else printf '[ci] WARNING: %s\n' "$*" >&2; fi
}
ci_error() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::error::$*"; else printf '[ci] ERROR: %s\n' "$*" >&2; fi
}
ci_die() {
  ci_error "$*"
  exit 1
}
ci_group() { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::group::$*"; else printf '\n=== %s\n' "$*" >&2; fi; }
ci_endgroup() { if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::endgroup::"; fi; }

# Append Markdown to the job summary (GitHub) or print it (local).
ci_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then printf '%s\n' "$*" >>"$GITHUB_STEP_SUMMARY"; else printf '%s\n' "$*"; fi
}

ci_require() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || ci_die "'${cmd}' is required (ci/scripts/install-tools.sh installs the pinned scanners)"
  done
}

ci_load_tool_versions() {
  # shellcheck source=../tool-versions.env
  source "${CI_REPO_ROOT}/ci/tool-versions.env"
}

# Manifest helpers (ci/projects/<project>.json).
# (tr -d '\r': Windows Python prints CRLF; harmless on Linux.)
ci_manifest() { python3 "${CI_REPO_ROOT}/ci/scripts/ci.py" manifest "$1" "$2" | tr -d '\r'; }
ci_manifest_list() {
  ci_manifest "$1" "$2" | python3 -c 'import json, sys; [print(x) for x in json.load(sys.stdin)]' | tr -d '\r'
}

ci_project_dir() {
  local project="$1"
  [[ -f "${CI_REPO_ROOT}/ci/projects/${project}.json" ]] || ci_die "unknown project '${project}'"
  echo "${CI_REPO_ROOT}/${project}"
}
