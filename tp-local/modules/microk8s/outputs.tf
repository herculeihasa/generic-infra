output "channel" {
  description = "MicroK8s snap channel tracked by the cluster."
  value       = var.channel
}

output "kubeconfig_path" {
  description = "Absolute path of the exported admin kubeconfig (known at plan time; the file exists after apply)."
  value       = local.kubeconfig_path
}

output "kubeconfig_context" {
  description = "Context name inside the exported kubeconfig."
  value       = "microk8s"
}

output "api_server_url" {
  description = "Kubernetes API server URL written in the kubeconfig."
  value       = local.api_server_url
}

output "install_id" {
  description = "ID of the install step (changes when MicroK8s is reinstalled); useful to sequence dependent steps."
  value       = terraform_data.install.id
}
