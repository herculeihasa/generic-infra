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
