output "kubeconfig_path" {
  description = "Kubeconfig used by the Kubernetes and Helm providers."
  value       = local.kubeconfig_path
}

output "kubeconfig_context" {
  description = "Kubeconfig context used by the Kubernetes and Helm providers."
  value       = var.kubeconfig_context
}

output "nodes" {
  description = "Cluster nodes seen by the Kubernetes provider: Ready status, kubelet version, OS image (connectivity and health check)."
  value       = local.node_health
}

output "namespaces" {
  description = "Managed namespaces with their security baseline and service accounts."
  value = {
    for name, ns in module.namespaces : name => {
      pod_security_enforce = ns.pod_security_enforce
      network_isolated     = ns.network_isolated
      service_accounts     = ns.service_account_names
    }
  }
}

output "storage_classes" {
  description = "StorageClasses managed here (in addition to microk8s-hostpath from the add-on)."
  value       = [for sc in kubernetes_storage_class_v1.hostpath_retain : sc.metadata[0].name]
}
