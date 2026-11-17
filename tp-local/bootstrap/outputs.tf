output "microk8s_channel" {
  description = "MicroK8s snap channel tracked by the cluster."
  value       = module.microk8s.channel
}

output "kubeconfig_path" {
  description = "Exported admin kubeconfig (pass it to environments/dev if not the default)."
  value       = module.microk8s.kubeconfig_path
}

output "kubeconfig_context" {
  description = "Context name inside the exported kubeconfig."
  value       = module.microk8s.kubeconfig_context
}

output "api_server_url" {
  description = "Kubernetes API server URL."
  value       = module.microk8s.api_server_url
}

output "next_steps" {
  description = "How to use the cluster."
  value       = <<-EOT
    export KUBECONFIG=${module.microk8s.kubeconfig_path}
    kubectl get nodes          # or: microk8s kubectl get nodes
    ../scripts/tf-init.sh environments/dev && terraform -chdir=../environments/dev plan
  EOT
}
