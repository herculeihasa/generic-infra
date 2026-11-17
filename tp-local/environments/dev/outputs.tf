output "kubeconfig_path" {
  description = "Kubeconfig used by the Kubernetes and Helm providers."
  value       = local.kubeconfig_path
}

output "kubeconfig_context" {
  description = "Kubeconfig context used by the Kubernetes and Helm providers."
  value       = var.kubeconfig_context
}
