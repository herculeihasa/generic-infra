#!/usr/bin/env bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# Shared helpers for the microk8s module scripts. Sourced, never executed.
#
# Every system path is overridable through environment variables so that the
# scripts can be tested with stubs on any machine (see tests/run.sh).
# -----------------------------------------------------------------------------

set -Eeuo pipefail

# Name the failing command: Terraform only shows the provisioner output.
trap 'printf "%s ERROR: command failed (exit %s): %s\n" "${TP_LOG_PREFIX:-[tp-local/microk8s]}" "$?" "$BASH_COMMAND" >&2' ERR

TP_LOG_PREFIX="${TP_LOG_PREFIX:-[tp-local/microk8s]}"
PID1_COMM_FILE="${PID1_COMM_FILE:-/proc/1/comm}"
PROC_VERSION_FILE="${PROC_VERSION_FILE:-/proc/version}"
MEMINFO_FILE="${MEMINFO_FILE:-/proc/meminfo}"
LOCK_DIR="${TP_LOCAL_LOCK_DIR:-${XDG_RUNTIME_DIR:-/tmp}/tp-local-microk8s.lock}"
LOCK_TIMEOUT_SECONDS="${LOCK_TIMEOUT_SECONDS:-900}"

log() { printf '%s %s\n' "$TP_LOG_PREFIX" "$*" >&2; }
warn() { log "WARNING: $*"; }
die() {
  log "ERROR: $*"
  exit 1
}
have() { command -v "$1" >/dev/null 2>&1; }

is_wsl() {
  [[ -n "${WSL_DISTRO_NAME:-}" ]] || grep -qi microsoft "$PROC_VERSION_FILE" 2>/dev/null
}

# Confinement-dependent group granting access to the microk8s CLI.
microk8s_group() {
  if [[ "${MICROK8S_CHANNEL:-}" == *-strict/* ]]; then echo "snap_microk8s"; else echo "microk8s"; fi
}

# Root privileges are obtained non-interactively: Terraform cannot answer a
# password prompt. The operator caches credentials with `sudo -v` first.
require_root_access() {
  local purpose="$1"
  [[ $EUID -eq 0 ]] && return 0
  if ! sudo -n true 2>/dev/null; then
    die "root privileges are required to ${purpose}. Run 'sudo -v' (credentials are cached ~15 min) and re-run 'terraform apply'."
  fi
}

as_root() {
  if [[ $EUID -eq 0 ]]; then "$@"; else sudo -n "$@"; fi
}

# The microk8s CLI works without sudo once the user is in the microk8s group
# AND the current session has picked the membership up. Fall back to sudo in
# the session that just added the membership.
mk8s() {
  if id -nG | tr ' ' '\n' | grep -qx "$(microk8s_group)"; then
    microk8s "$@"
  else
    require_root_access "run 'microk8s $1' (group membership not active in this session)"
    as_root microk8s "$@"
  fi
}

microk8s_installed() { snap list microk8s >/dev/null 2>&1; }

# Channel currently tracked by the snap, e.g. "1.35/stable".
microk8s_tracking() { snap list microk8s 2>/dev/null | awk 'NR == 2 { print $4 }'; }

wait_ready() {
  local timeout="${1:-600}"
  log "waiting for MicroK8s to be ready (timeout ${timeout}s)"
  mk8s status --wait-ready --timeout "$timeout" >/dev/null ||
    die "MicroK8s did not become ready within ${timeout}s (see 'microk8s inspect')."
  mk8s kubectl wait --for=condition=Ready node --all --timeout="${timeout}s" >/dev/null ||
    die "the Kubernetes node did not become Ready within ${timeout}s."
  log "MicroK8s is ready"
}

# Portable mutual exclusion (mkdir is atomic): serialises concurrent
# `microk8s enable/disable` calls issued by parallel Terraform resources.
acquire_lock() {
  local waited=0
  until mkdir "$LOCK_DIR" 2>/dev/null; do
    if ((waited >= LOCK_TIMEOUT_SECONDS)); then
      die "could not acquire ${LOCK_DIR} after ${LOCK_TIMEOUT_SECONDS}s. If no Terraform run is active, remove it: rmdir '${LOCK_DIR}'."
    fi
    sleep 2
    waited=$((waited + 2))
  done
  # shellcheck disable=SC2064 # expand LOCK_DIR now, on purpose
  trap "rmdir '${LOCK_DIR}' 2>/dev/null || true" EXIT
}
