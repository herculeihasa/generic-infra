variable "channel" {
  description = "MicroK8s snap channel, i.e. Kubernetes minor version and risk level (e.g. \"1.35/stable\"). Changing it refreshes the snap in place (`snap refresh`), keeping cluster data. \"-strict\" tracks select strict confinement."
  type        = string
  default     = "1.35/stable"

  validation {
    condition     = can(regex("^(latest|[0-9]+\\.[0-9]+)(-strict)?/(stable|candidate|beta|edge)$", var.channel))
    error_message = "channel must look like <track>/<risk>, e.g. 1.35/stable, 1.35-strict/stable or latest/edge."
  }
}

variable "kubeconfig_path" {
  description = "Where the admin kubeconfig is exported (`~` is expanded). Created with 0600 permissions; removed on destroy. Keep it outside Git repositories: it embeds the cluster admin certificate."
  type        = string
  default     = "~/.kube/tp-local-microk8s.yaml"

  validation {
    condition     = length(trimspace(var.kubeconfig_path)) > 0 && !endswith(var.kubeconfig_path, "/")
    error_message = "kubeconfig_path must be a file path."
  }
}

variable "api_server_address" {
  description = "Address written in the exported kubeconfig. 127.0.0.1 (default) survives WSL IP changes and is part of the MicroK8s certificate SANs."
  type        = string
  default     = "127.0.0.1"

  validation {
    condition     = can(regex("^[A-Za-z0-9.-]+$", var.api_server_address))
    error_message = "api_server_address must be an IP address or host name."
  }
}

variable "wait_timeout_seconds" {
  description = "Timeout of every readiness wait (MicroK8s services, node Ready, add-ons), 60-3600 seconds."
  type        = number
  default     = 600

  validation {
    condition     = var.wait_timeout_seconds >= 60 && var.wait_timeout_seconds <= 3600
    error_message = "wait_timeout_seconds must be between 60 and 3600."
  }
}

variable "addons" {
  description = "MicroK8s add-ons to enable (name => { args }). args are passed verbatim after the add-on name, e.g. registry = { args = [\"--size\", \"40Gi\"] }. Removing an entry disables that add-on (volume data kept). Add-ons not listed here are left untouched. Names and arguments are validated (no shell metacharacters)."
  type = map(object({
    args = optional(list(string), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for name in keys(var.addons) : can(regex("^[a-z0-9][a-z0-9-]*$", name))])
    error_message = "Add-on names must be lowercase letters, digits and hyphens (e.g. hostpath-storage)."
  }

  validation {
    # Arguments travel through an environment variable and are never
    # evaluated by a shell; this allowlist keeps them unambiguous.
    condition     = alltrue(flatten([for a in values(var.addons) : [for arg in a.args : can(regex("^[A-Za-z0-9=:,./_@+-]+$", arg))]]))
    error_message = "Add-on arguments may only contain letters, digits and = : , . / _ @ + -"
  }
}

variable "uninstall_on_destroy" {
  description = "Remove the MicroK8s snap AND all cluster data on `terraform destroy`. False (default) keeps MicroK8s installed and only removes what Terraform added on top of it."
  type        = bool
  default     = false
}
