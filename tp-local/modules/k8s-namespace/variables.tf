variable "name" {
  description = "Namespace name (RFC 1123 label). System namespaces are refused: the module creates and owns the namespace."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.name))
    error_message = "name must be a lowercase RFC 1123 label (max 63 characters)."
  }

  validation {
    condition     = !contains(["default", "kube-system", "kube-public", "kube-node-lease", "ingress"], var.name)
    error_message = "System or add-on namespaces cannot be managed by this module."
  }
}

variable "labels" {
  description = "Additional namespace labels."
  type        = map(string)
  default     = {}
}

variable "annotations" {
  description = "Namespace annotations."
  type        = map(string)
  default     = {}
}

variable "pod_security" {
  description = "Pod Security Admission levels (privileged | baseline | restricted): enforce rejects violating pods, audit/warn only report."
  type = object({
    enforce = optional(string, "baseline")
    audit   = optional(string, "restricted")
    warn    = optional(string, "restricted")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for level in [var.pod_security.enforce, var.pod_security.audit, var.pod_security.warn] :
      contains(["privileged", "baseline", "restricted"], level)
    ])
    error_message = "pod_security levels must be privileged, baseline or restricted."
  }
}

variable "resource_quota" {
  description = "ResourceQuota `hard` limits (e.g. { \"requests.cpu\" = \"2\", \"limits.memory\" = \"8Gi\", pods = \"30\" }). Empty = no quota. With CPU/memory quotas, pair it with limit_range so pods without resources still get defaults."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "limit_range" {
  description = "Container defaults (default_request / default_limit) and optional max, e.g. { default_request = { cpu = \"100m\", memory = \"128Mi\" }, default_limit = { cpu = \"500m\", memory = \"512Mi\" } }. Null = no LimitRange."
  type = object({
    default_request = map(string)
    default_limit   = map(string)
    max             = optional(map(string), {})
  })
  default = null
}

variable "network_policy" {
  description = "Ingress isolation. default_deny_ingress blocks all inbound traffic to the namespace except from the same namespace (allow_same_namespace) and from allow_from_namespaces (e.g. [\"ingress\"] for the MicroK8s ingress controller). Egress stays open."
  type = object({
    default_deny_ingress  = optional(bool, true)
    allow_same_namespace  = optional(bool, true)
    allow_from_namespaces = optional(list(string), [])
  })
  default  = {}
  nullable = false
}

variable "service_accounts" {
  description = "Service accounts to create (name => settings). cluster_role (e.g. \"edit\", \"view\") is bound inside this namespace only. Tokens are not automounted unless automount_token = true."
  type = map(object({
    cluster_role    = optional(string)
    automount_token = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.service_accounts) : can(regex("^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$", name))])
    error_message = "service account names must be lowercase RFC 1123 subdomains."
  }
}

variable "role_bindings" {
  description = "Namespace-scoped bindings of ClusterRoles to users or groups (binding name => { cluster_role, subjects = [{ kind = User|Group, name }] })."
  type = map(object({
    cluster_role = string
    subjects = list(object({
      kind = string
      name = string
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue(flatten([
      for binding in values(var.role_bindings) : [for s in binding.subjects : contains(["User", "Group"], s.kind)]
    ]))
    error_message = "role_bindings subjects must be of kind User or Group (service accounts go through service_accounts)."
  }
}
