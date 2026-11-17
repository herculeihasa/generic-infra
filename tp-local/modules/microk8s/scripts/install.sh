#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Install MicroK8s (idempotent) and give the current user CLI access.
#
# Environment (set by Terraform):
#   MICROK8S_CHANNEL      snap channel, e.g. 1.35/stable
#   WAIT_TIMEOUT_SECONDS  readiness timeout
#
# Root is needed only for `snap install` and `usermod` (sudo -n).
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${MICROK8S_CHANNEL:?MICROK8S_CHANNEL is required}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-600}"

bash "$(dirname "${BASH_SOURCE[0]}")/preflight.sh"

if microk8s_installed; then
  log "MicroK8s already installed (tracking $(microk8s_tracking)); channel changes are applied by set-channel.sh"
else
  require_root_access "install the microk8s snap"
  flags=("--channel=${MICROK8S_CHANNEL}")
  # Classic confinement unless a "-strict" track is requested.
  [[ "$MICROK8S_CHANNEL" == *-strict/* ]] || flags+=("--classic")
  log "installing MicroK8s from ${MICROK8S_CHANNEL}"
  as_root snap install microk8s "${flags[@]}"
fi

user="$(id -un)"
group="$(microk8s_group)"
if ! id -nG "$user" | tr ' ' '\n' | grep -qx "$group"; then
  require_root_access "add ${user} to the ${group} group"
  as_root usermod -a -G "$group" "$user"
  log "added ${user} to '${group}': new shells use microk8s without sudo (current one: 'newgrp ${group}')"
fi

mkdir -p "${HOME}/.kube"
chmod 700 "${HOME}/.kube"

wait_ready "$WAIT_TIMEOUT_SECONDS"
