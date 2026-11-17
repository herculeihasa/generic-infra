#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Host prerequisites for MicroK8s. Read-only; safe to run by hand:
#   bash tp-local/modules/microk8s/scripts/preflight.sh
#
# Hard requirements (exit 1): Linux, systemd as PID 1, snapd.
# Recommendations (warnings): WSL detected, >= MIN_MEMORY_MB of RAM,
# >= MIN_DISK_GB free under /var.
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MIN_MEMORY_MB="${MIN_MEMORY_MB:-4096}"
MIN_DISK_GB="${MIN_DISK_GB:-20}"
DISK_PATH="${DISK_PATH:-/var}"

[[ "$(uname -s)" == "Linux" ]] || die "MicroK8s requires Linux: run Terraform from WSL Ubuntu, not from Windows."

if is_wsl; then
  log "WSL detected (${WSL_DISTRO_NAME:-unknown distribution})"
else
  warn "not running in WSL: continuing (the module works on any systemd-based Ubuntu host)."
fi

pid1="$(tr -d '[:space:]' <"$PID1_COMM_FILE" 2>/dev/null || true)"
if [[ "$pid1" != "systemd" ]]; then
  die "systemd is not PID 1 (found '${pid1:-unknown}'). snapd needs systemd: in WSL set '[boot] systemd=true' in /etc/wsl.conf (tp-local/scripts/wsl/prepare-wsl.sh does it), then run 'wsl --shutdown' from Windows."
fi

have snap || die "snapd is not installed: run 'sudo tp-local/scripts/wsl/prepare-wsl.sh' (or 'sudo apt-get install -y snapd')."

mem_mb="$(awk '/^MemTotal:/ { printf "%d", $2 / 1024 }' "$MEMINFO_FILE" 2>/dev/null || echo 0)"
if ((mem_mb < MIN_MEMORY_MB)); then
  warn "${mem_mb} MiB of RAM visible (recommended >= ${MIN_MEMORY_MB} MiB). In WSL raise 'memory=' in %UserProfile%\\.wslconfig (see tp-local/scripts/host/wslconfig.example)."
fi

if have df; then
  free_gb="$(df -Pk "$DISK_PATH" 2>/dev/null | awk 'NR == 2 { printf "%d", $4 / 1048576 }')"
  if [[ -n "$free_gb" ]] && ((free_gb < MIN_DISK_GB)); then
    warn "${free_gb} GiB free under ${DISK_PATH} (recommended >= ${MIN_DISK_GB} GiB for images and volumes)."
  fi
fi

log "preflight checks passed"
