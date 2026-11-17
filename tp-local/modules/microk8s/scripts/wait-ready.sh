#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Cluster readiness gate after add-on changes. Safe to run by hand:
#   bash tp-local/modules/microk8s/scripts/wait-ready.sh
#
# 1. MicroK8s services up and node Ready;
# 2. every Deployment Available (add-on controllers, CoreDNS, ...);
# 3. every DaemonSet rolled out (Calico, ingress controller, ...).
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-600}"

wait_ready "$WAIT_TIMEOUT_SECONDS"

log "waiting for all deployments to be Available"
mk8s kubectl wait --for=condition=Available deployment --all --all-namespaces \
  --timeout="${WAIT_TIMEOUT_SECONDS}s" >/dev/null ||
  die "some deployments are not Available: microk8s kubectl get deploy -A"

log "waiting for all daemonsets to be rolled out"
while read -r namespace name; do
  [[ -n "$name" ]] || continue
  mk8s kubectl rollout status "daemonset/${name}" -n "$namespace" \
    --timeout="${WAIT_TIMEOUT_SECONDS}s" >/dev/null ||
    die "daemonset ${namespace}/${name} is not ready"
done < <(mk8s kubectl get daemonsets --all-namespaces \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}')

log "cluster and add-ons are ready"
