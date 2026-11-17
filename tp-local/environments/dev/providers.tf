# Both providers read the kubeconfig exported by ../../bootstrap (MicroK8s
# admin credentials, server rewritten to https://127.0.0.1:16443). The
# cluster is created by a SEPARATE apply (bootstrap), as recommended by the
# Kubernetes provider: configuring it from resources of the same apply leads
# to unpredictable provider configuration errors.

provider "kubernetes" {
  config_path    = local.kubeconfig_path
  config_context = var.kubeconfig_context
}

provider "helm" {
  kubernetes = {
    config_path    = local.kubeconfig_path
    config_context = var.kubeconfig_context
  }
}
