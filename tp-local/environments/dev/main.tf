# =============================================================================
# Environment: dev (local MicroK8s cluster)
#
# Stage 2 of tp-local: Kubernetes resources (namespaces, RBAC, storage) and
# Helm releases on the cluster provisioned by ../../bootstrap (stage 1).
#
#   main.tf (this file): platform baseline (namespaces, RBAC, storage, nodes)
#   helm.tf:             Helm releases (application layer)
# =============================================================================

# Reading the nodes doubles as a connectivity check: the plan fails early if
# the kubeconfig or the cluster is not usable.
data "kubernetes_nodes" "all" {}

module "namespaces" {
  source   = "../../modules/k8s-namespace"
  for_each = var.namespaces

  name           = each.key
  labels         = merge(local.common_labels, each.value.labels)
  pod_security   = each.value.pod_security
  resource_quota = each.value.resource_quota
  limit_range    = each.value.limit_range
  network_policy = {
    default_deny_ingress  = each.value.default_deny_ingress
    allow_same_namespace  = true
    allow_from_namespaces = each.value.allow_ingress_from_namespaces
  }
  service_accounts = each.value.service_accounts
  role_bindings    = each.value.role_bindings
}

# MicroK8s' hostpath-storage add-on provides "microk8s-hostpath" (Delete
# policy). This class keeps volumes after their claims are deleted.
resource "kubernetes_storage_class_v1" "hostpath_retain" {
  count = var.retain_storage_class_enabled ? 1 : 0

  metadata {
    name   = "microk8s-hostpath-retain"
    labels = local.common_labels
  }

  storage_provisioner    = "microk8s.io/hostpath"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = false
}

# Optional labels on every node (single-node MicroK8s: the WSL host).
resource "kubernetes_labels" "nodes" {
  for_each = length(var.node_labels) > 0 ? toset(local.node_names) : toset([])

  api_version   = "v1"
  kind          = "Node"
  field_manager = "terraform-tp-local"
  labels        = var.node_labels

  metadata {
    name = each.key
  }
}
