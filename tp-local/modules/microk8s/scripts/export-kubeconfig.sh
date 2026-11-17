#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Export the MicroK8s admin kubeconfig for Terraform providers and kubectl.
#
# Environment (set by Terraform):
#   KUBECONFIG_PATH     destination file (created 0600, atomically replaced)
#   API_SERVER_ADDRESS  address written in `server:` (default 127.0.0.1)
#
# `microk8s config` writes the current eth0 IP, which changes on every WSL
# restart. 127.0.0.1 is in the API server certificate SANs and stays valid
# (Windows tools also reach it through WSL localhost forwarding).
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${KUBECONFIG_PATH:?KUBECONFIG_PATH is required}"
API_SERVER_ADDRESS="${API_SERVER_ADDRESS:-127.0.0.1}"
API_SERVER_PORT="${API_SERVER_PORT:-16443}"

umask 077
mkdir -p "$(dirname "$KUBECONFIG_PATH")"
tmp="$(mktemp "${KUBECONFIG_PATH}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

mk8s config |
  sed -E "s#(server: https://)[^/]+:${API_SERVER_PORT}#\1${API_SERVER_ADDRESS}:${API_SERVER_PORT}#" >"$tmp"

grep -q "server: https://${API_SERVER_ADDRESS}:${API_SERVER_PORT}" "$tmp" ||
  die "unexpected 'microk8s config' output: no API server URL on port ${API_SERVER_PORT}."

chmod 600 "$tmp"
mv -f "$tmp" "$KUBECONFIG_PATH"
trap - EXIT
log "kubeconfig written to ${KUBECONFIG_PATH} (server https://${API_SERVER_ADDRESS}:${API_SERVER_PORT})"

# Non-fatal reachability probe of the rewritten endpoint.
if have curl && ! curl -fsSk --max-time 5 "https://${API_SERVER_ADDRESS}:${API_SERVER_PORT}/readyz" >/dev/null 2>&1; then
  warn "https://${API_SERVER_ADDRESS}:${API_SERVER_PORT}/readyz did not answer: check the address or wait for the API server."
fi
