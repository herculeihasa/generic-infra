variable "microk8s_channel" {
  description = "MicroK8s snap channel (Kubernetes minor version / risk), e.g. \"1.35/stable\". List them with `snap info microk8s`."
  type        = string
  default     = "1.35/stable"
}

variable "kubeconfig_path" {
  description = "Where the admin kubeconfig is exported. environments/dev reads the same default."
  type        = string
  default     = "~/.kube/tp-local-microk8s.yaml"
}

variable "api_server_address" {
  description = "Address written in the exported kubeconfig (127.0.0.1 survives WSL IP changes)."
  type        = string
  default     = "127.0.0.1"
}

variable "wait_timeout_seconds" {
  description = "Readiness timeout for MicroK8s operations."
  type        = number
  default     = 600
}

variable "uninstall_on_destroy" {
  description = "Remove MicroK8s and ALL cluster data on `terraform destroy` (default: keep it installed)."
  type        = bool
  default     = false
}
