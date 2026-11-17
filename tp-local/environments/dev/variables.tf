# -----------------------------------------------------------------------------
# Cluster access
# -----------------------------------------------------------------------------

variable "kubeconfig_path" {
  description = "Kubeconfig written by the bootstrap stage (`terraform -chdir=../../bootstrap output -raw kubeconfig_path`). `~` is expanded."
  type        = string
  default     = "~/.kube/tp-local-microk8s.yaml"
}

variable "kubeconfig_context" {
  description = "Context to use in the kubeconfig (MicroK8s names it \"microk8s\")."
  type        = string
  default     = "microk8s"
}

variable "environment" {
  description = "Environment name, used in labels."
  type        = string

  validation {
    condition     = contains(["dev", "rec"], var.environment)
    error_message = "environment must be dev or rec."
  }
}

# -----------------------------------------------------------------------------
# Platform baseline
# -----------------------------------------------------------------------------

variable "namespaces" {
  description = <<-EOT
    Namespaces to create (name => settings), each with the k8s-namespace module baseline:
    Pod Security Admission levels, optional ResourceQuota / LimitRange, ingress isolation
    (default deny + same namespace + allow_ingress_from_namespaces), service accounts bound to
    ClusterRoles inside the namespace, and user/group role bindings.
  EOT
  type = map(object({
    labels = optional(map(string), {})
    pod_security = optional(object({
      enforce = optional(string, "baseline")
      audit   = optional(string, "restricted")
      warn    = optional(string, "restricted")
    }), {})
    resource_quota = optional(map(string), {})
    limit_range = optional(object({
      default_request = map(string)
      default_limit   = map(string)
      max             = optional(map(string), {})
    }))
    default_deny_ingress          = optional(bool, true)
    allow_ingress_from_namespaces = optional(list(string), [])
    service_accounts = optional(map(object({
      cluster_role    = optional(string)
      automount_token = optional(bool, false)
    })), {})
    role_bindings = optional(map(object({
      cluster_role = string
      subjects     = list(object({ kind = string, name = string }))
    })), {})
  }))
  default = {}
}

variable "retain_storage_class_enabled" {
  description = "Create the \"microk8s-hostpath-retain\" StorageClass (hostpath volumes kept after their claim is deleted)."
  type        = bool
  default     = true
}

variable "node_labels" {
  description = "Labels applied to every node (empty = none)."
  type        = map(string)
  default     = {}
}
