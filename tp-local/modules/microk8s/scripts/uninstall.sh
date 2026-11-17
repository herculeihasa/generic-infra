#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Destroy-time action of the install resource.
#
# UNINSTALL=true  -> `snap remove --purge microk8s` (deletes ALL cluster data)
# UNINSTALL=false -> keep MicroK8s installed (default, safe)
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ "${UNINSTALL:-false}" != "true" ]]; then
  log "keeping MicroK8s installed (uninstall_on_destroy = false); remove it manually with 'sudo snap remove --purge microk8s'"
  exit 0
fi

if ! microk8s_installed; then
  log "MicroK8s is not installed: nothing to remove"
  exit 0
fi

require_root_access "remove the microk8s snap"
log "removing MicroK8s and ALL its data (uninstall_on_destroy = true)"
as_root snap remove --purge microk8s
