# -----------------------------------------------------------------------------
# tp-local dev: NON-SENSITIVE values only (this file is committed).
# -----------------------------------------------------------------------------

environment = "dev"

# Written by ../../bootstrap (defaults shown).
kubeconfig_path    = "~/.kube/tp-local-microk8s.yaml"
kubeconfig_context = "microk8s"

namespaces = {
  # Application workloads: isolated, quota-bound, reachable from the
  # MicroK8s ingress controller only.
  apps = {
    pod_security = { enforce = "baseline" }
    resource_quota = {
      "requests.cpu"           = "2"
      "requests.memory"        = "4Gi"
      "limits.cpu"             = "4"
      "limits.memory"          = "8Gi"
      "pods"                   = "30"
      "persistentvolumeclaims" = "10"
    }
    limit_range = {
      default_request = { cpu = "100m", memory = "128Mi" }
      default_limit   = { cpu = "500m", memory = "512Mi" }
    }
    allow_ingress_from_namespaces = ["ingress"]
    service_accounts = {
      # Identity for a future deployment pipeline: may manage workloads in
      # "apps" only, no token mounted in pods.
      app-deployer = { cluster_role = "edit" }
    }
  }

  # Experiments: open network, privileged pods allowed (still warned).
  sandbox = {
    pod_security         = { enforce = "privileged", audit = "baseline", warn = "baseline" }
    default_deny_ingress = false
  }
}

retain_storage_class_enabled = true

node_labels = {
  "tp-local/role" = "dev"
}
