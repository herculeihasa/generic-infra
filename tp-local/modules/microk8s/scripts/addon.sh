#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Enable or disable one MicroK8s add-on (idempotent).
#
#   addon.sh enable|disable
#
# Environment (set by Terraform):
#   ADDON_NAME   add-on name, e.g. hostpath-storage
#   ADDON_ARGS   extra arguments, one per line (never evaluated by a shell)
#
# Calls are serialised with a lock: Terraform creates add-on resources in
# parallel and concurrent `microk8s enable` runs conflict. `disable` answers
# "n" to any prompt (e.g. hostpath-storage asking to delete volume data).
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

action="${1:-}"
: "${ADDON_NAME:?ADDON_NAME is required}"
[[ "$ADDON_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "invalid add-on name '${ADDON_NAME}'"

args=()
if [[ -n "${ADDON_ARGS:-}" ]]; then
  mapfile -t args <<<"$ADDON_ARGS"
fi

case "$action" in
  enable)
    acquire_lock
    log "enabling add-on ${ADDON_NAME} ${args[*]:-}"
    mk8s enable "$ADDON_NAME" "${args[@]}" </dev/null
    ;;
  disable)
    if ! microk8s_installed; then
      log "MicroK8s is not installed: nothing to disable for ${ADDON_NAME}"
      exit 0
    fi
    acquire_lock
    log "disabling add-on ${ADDON_NAME} (data kept)"
    printf 'n\n' | mk8s disable "$ADDON_NAME"
    ;;
  *) die "usage: addon.sh enable|disable" ;;
esac
