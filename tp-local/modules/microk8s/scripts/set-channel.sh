#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Align the tracked snap channel with MICROK8S_CHANNEL (idempotent).
# A different track/risk is applied in place with `snap refresh` (keeps the
# cluster data). Switching between classic and strict confinement is refused:
# it requires a reinstall.
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${MICROK8S_CHANNEL:?MICROK8S_CHANNEL is required}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-600}"

microk8s_installed || die "MicroK8s is not installed (install.sh must run first)."

current="$(microk8s_tracking)"
if [[ "$current" == "$MICROK8S_CHANNEL" ]]; then
  log "already tracking ${current}"
  exit 0
fi

current_strict=false
wanted_strict=false
[[ "$current" == *-strict/* ]] && current_strict=true
[[ "$MICROK8S_CHANNEL" == *-strict/* ]] && wanted_strict=true
if [[ "$current_strict" != "$wanted_strict" ]]; then
  die "cannot move between classic and strict confinement (${current} -> ${MICROK8S_CHANNEL}) with snap refresh: reinstall instead (uninstall_on_destroy = true, destroy, apply)."
fi

require_root_access "refresh the microk8s snap to ${MICROK8S_CHANNEL}"
log "refreshing MicroK8s ${current} -> ${MICROK8S_CHANNEL}"
as_root snap refresh microk8s --channel="${MICROK8S_CHANNEL}"

wait_ready "$WAIT_TIMEOUT_SECONDS"
