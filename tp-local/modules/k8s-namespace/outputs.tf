output "name" {
  description = "Namespace name (depends on the namespace resource: use it to order dependent resources such as Helm releases)."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "service_account_names" {
  description = "Service accounts created in the namespace."
  value       = sort([for sa in kubernetes_service_account_v1.this : sa.metadata[0].name])
}

output "pod_security_enforce" {
  description = "Enforced Pod Security Admission level."
  value       = var.pod_security.enforce
}

output "network_isolated" {
  description = "Whether inbound traffic is denied by default."
  value       = var.network_policy.default_deny_ingress
}
