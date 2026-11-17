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
  description = "Timeout of every readiness wait (MicroK8s services, node Ready, add-ons)."
  type        = number
  default     = 600

  validation {
    condition     = var.wait_timeout_seconds >= 60 && var.wait_timeout_seconds <= 3600
    error_message = "wait_timeout_seconds must be between 60 and 3600."
  }
}

variable "uninstall_on_destroy" {
  description = "Remove the MicroK8s snap AND all cluster data on `terraform destroy`. False (default) keeps MicroK8s installed and only removes what Terraform added on top of it."
  type        = bool
  default     = false
}
