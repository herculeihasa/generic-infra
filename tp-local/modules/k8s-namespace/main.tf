# =============================================================================
# Namespace baseline: Pod Security Admission, quotas, default limits,
# ingress isolation, service accounts and namespace-scoped RBAC.
# =============================================================================

locals {
  labels = merge(var.labels, {
    "app.kubernetes.io/managed-by"       = "terraform"
    "pod-security.kubernetes.io/enforce" = var.pod_security.enforce
    "pod-security.kubernetes.io/audit"   = var.pod_security.audit
    "pod-security.kubernetes.io/warn"    = var.pod_security.warn
  })

  bound_service_accounts = { for name, sa in var.service_accounts : name => sa if sa.cluster_role != null }
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name        = var.name
    labels      = local.labels
    annotations = var.annotations
  }
}

# Pods that do not need the Kubernetes API should not get a token.
resource "kubernetes_default_service_account_v1" "this" {
  metadata {
    name      = "default"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  automount_service_account_token = false
}

resource "kubernetes_resource_quota_v1" "this" {
  count = length(var.resource_quota) > 0 ? 1 : 0

  metadata {
    name      = "${var.name}-quota"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    hard = var.resource_quota
  }
}

resource "kubernetes_limit_range_v1" "this" {
  count = var.limit_range == null ? 0 : 1

  metadata {
    name      = "${var.name}-limits"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    limit {
      type            = "Container"
      default_request = var.limit_range.default_request
      default         = var.limit_range.default_limit
      max             = length(var.limit_range.max) > 0 ? var.limit_range.max : null
    }
  }
}

# --- Ingress isolation (NetworkPolicies are additive: deny-all + allows) -------

resource "kubernetes_network_policy_v1" "default_deny_ingress" {
  count = var.network_policy.default_deny_ingress ? 1 : 0

  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy_v1" "allow_same_namespace" {
  count = var.network_policy.default_deny_ingress && var.network_policy.allow_same_namespace ? 1 : 0

  metadata {
    name      = "allow-same-namespace"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {}
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "allow_from_namespaces" {
  count = var.network_policy.default_deny_ingress && length(var.network_policy.allow_from_namespaces) > 0 ? 1 : 0

  metadata {
    name      = "allow-from-namespaces"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_expressions {
            key      = "kubernetes.io/metadata.name"
            operator = "In"
            values   = var.network_policy.allow_from_namespaces
          }
        }
      }
    }
  }
}

# --- Service accounts and RBAC ------------------------------------------------------

resource "kubernetes_service_account_v1" "this" {
  for_each = var.service_accounts

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = { "app.kubernetes.io/managed-by" = "terraform" }
  }

  automount_service_account_token = each.value.automount_token
}

resource "kubernetes_role_binding_v1" "service_account" {
  for_each = local.bound_service_accounts

  metadata {
    name      = "${each.key}-${each.value.cluster_role}"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = each.value.cluster_role
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.this[each.key].metadata[0].name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
}

resource "kubernetes_role_binding_v1" "this" {
  for_each = var.role_bindings

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = each.value.cluster_role
  }

  dynamic "subject" {
    for_each = each.value.subjects

    content {
      api_group = "rbac.authorization.k8s.io"
      kind      = subject.value.kind
      name      = subject.value.name
    }
  }
}
