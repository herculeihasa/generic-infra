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

# Applications. podinfo is a tiny web app used as the Helm/ingress smoke test:
#   curl -H 'Host: podinfo.localtest.me' http://$(hostname -I | awk '{print $1}')/
helm_releases = {
  podinfo = {
    namespace   = "apps"
    repository  = "https://stefanprodan.github.io/podinfo"
    chart       = "podinfo"
    version     = "6.17.0"
    values_yaml = <<-YAML
      replicaCount: 1
      resources:
        requests: { cpu: 10m, memory: 32Mi }
        limits: { cpu: 100m, memory: 64Mi }
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: { drop: ["ALL"] }
        seccompProfile: { type: RuntimeDefault }
      ingress:
        enabled: true
        className: public   # MicroK8s ingress add-on class
        hosts:
          - host: podinfo.localtest.me
            paths:
              - path: /
                pathType: ImplementationSpecific
    YAML
  }
}

node_labels = {
  "tp-local/role" = "dev"
}
