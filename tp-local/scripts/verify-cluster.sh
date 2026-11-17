#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Post-deployment verification of the local cluster. Run in WSL Ubuntu:
#   tp-local/scripts/verify-cluster.sh [--skip-apps]
#
# Checks, in order (exit 1 at the end if any failed):
#   1. kubeconfig present, mode 600, API server /readyz reachable through it
#   2. node(s) Ready
#   3. expected add-ons enabled (EXPECTED_ADDONS, space separated)
#   4. managed namespaces present (EXPECTED_NAMESPACES)
#   5. Helm reachable, releases deployed
#   6. podinfo answers through the ingress controller (unless --skip-apps)
#
# Uses kubectl/helm when installed, otherwise `microk8s kubectl` / `microk8s helm`.
# -----------------------------------------------------------------------------
set -uo pipefail

KUBECONFIG_PATH="${KUBECONFIG_PATH:-$HOME/.kube/tp-local-microk8s.yaml}"
EXPECTED_ADDONS="${EXPECTED_ADDONS:-dns rbac hostpath-storage metrics-server ingress}"
EXPECTED_NAMESPACES="${EXPECTED_NAMESPACES:-apps sandbox}"
APP_HOST="${APP_HOST:-podinfo.localtest.me}"
skip_apps=false
[[ "${1:-}" == "--skip-apps" ]] && skip_apps=true

failures=0
ok() { printf '[ OK ] %s\n' "$*"; }
ko() {
  printf '[FAIL] %s\n' "$*"
  failures=$((failures + 1))
}

kubectl_cmd() {
  if command -v kubectl >/dev/null 2>&1; then
    kubectl --kubeconfig "$KUBECONFIG_PATH" "$@"
  else
    microk8s kubectl "$@"
  fi
}

helm_cmd() {
  if command -v helm >/dev/null 2>&1; then
    helm --kubeconfig "$KUBECONFIG_PATH" "$@"
  else
    microk8s helm "$@"
  fi
}

# 1. kubeconfig and API server --------------------------------------------------
if [[ -f "$KUBECONFIG_PATH" ]]; then
  mode="$(stat -c %a "$KUBECONFIG_PATH" 2>/dev/null || echo "?")"
  [[ "$mode" == "600" ]] && ok "kubeconfig ${KUBECONFIG_PATH} (mode 600)" || ko "kubeconfig mode is ${mode}, expected 600"
else
  ko "kubeconfig ${KUBECONFIG_PATH} not found (apply tp-local/bootstrap first)"
fi
if kubectl_cmd get --raw=/readyz >/dev/null 2>&1; then
  ok "API server ready ($(grep -m1 'server:' "$KUBECONFIG_PATH" 2>/dev/null | awk '{print $2}'))"
else
  ko "API server not reachable"
fi

# 2. nodes ------------------------------------------------------------------------
not_ready="$(kubectl_cmd get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" { print $1 }')"
if [[ -z "$(kubectl_cmd get nodes --no-headers 2>/dev/null)" ]]; then
  ko "no node listed"
elif [[ -n "$not_ready" ]]; then
  ko "nodes not Ready: ${not_ready}"
else
  ok "all nodes Ready"
fi

# 3. add-ons ------------------------------------------------------------------------
if command -v microk8s >/dev/null 2>&1; then
  status="$(microk8s status --format short 2>/dev/null || true)"
  for addon in $EXPECTED_ADDONS; do
    if grep -Eq "^[a-z]+/${addon}: enabled" <<<"$status"; then
      ok "add-on ${addon} enabled"
    else
      ko "add-on ${addon} not enabled"
    fi
  done
else
  ko "microk8s CLI not found"
fi

# 4. namespaces ---------------------------------------------------------------------
for ns in $EXPECTED_NAMESPACES; do
  if kubectl_cmd get namespace "$ns" >/dev/null 2>&1; then
    ok "namespace ${ns} present"
  else
    ko "namespace ${ns} missing (apply tp-local/environments/dev)"
  fi
done

# 5. Helm ---------------------------------------------------------------------------
if releases="$(helm_cmd list --all-namespaces 2>/dev/null)"; then
  failed_releases="$(awk 'NR > 1 && $8 != "deployed" { print $1 "(" $8 ")" }' <<<"$releases")"
  [[ -z "$failed_releases" ]] && ok "Helm reachable; releases deployed: $(awk 'NR > 1 { printf "%s ", $1 }' <<<"$releases")" ||
    ko "Helm releases not deployed: ${failed_releases}"
else
  ko "Helm cannot reach the cluster"
fi

# 6. application through the ingress -------------------------------------------------
if [[ "$skip_apps" == "false" ]]; then
  node_ip="$(hostname -I 2>/dev/null | awk '{ print $1 }')"
  body="$(curl -fsS --max-time 10 -H "Host: ${APP_HOST}" "http://${node_ip:-127.0.0.1}/" 2>/dev/null || true)"
  if grep -q '"hostname"' <<<"$body"; then
    ok "http://${APP_HOST} answers through the ingress (node ${node_ip})"
  else
    ko "http://${APP_HOST} did not answer through the ingress (node ${node_ip:-unknown})"
  fi
fi

echo
if ((failures > 0)); then
  echo "verify-cluster: ${failures} check(s) failed"
  exit 1
fi
echo "verify-cluster: all checks passed"
