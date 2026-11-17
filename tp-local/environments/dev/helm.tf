# =============================================================================
# Application layer: Helm releases
#
# Kept apart from the platform baseline (main.tf): releases can only target
# namespaces managed here, so quotas, limits, Pod Security and network
# policies are in place before any chart is installed.
# =============================================================================

resource "helm_release" "this" {
  for_each = var.helm_releases

  name       = each.key
  namespace  = module.namespaces[each.value.namespace].name
  repository = each.value.repository
  chart      = each.value.chart
  version    = each.value.version
  values     = trimspace(each.value.values_yaml) == "" ? [] : [each.value.values_yaml]

  create_namespace = false
  atomic           = true # roll back a failed install/upgrade
  cleanup_on_fail  = true
  wait             = true
  timeout          = each.value.timeout_seconds
  max_history      = 5
}
