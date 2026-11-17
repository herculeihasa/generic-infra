locals {
  kubeconfig_path = pathexpand(var.kubeconfig_path)

  common_labels = {
    "app.kubernetes.io/part-of" = "tp-local"
    "tp-local/environment"      = var.environment
  }

  node_names = sort([for node in data.kubernetes_nodes.all.nodes : node.metadata[0].name])

  # Ready condition per node, for the health output.
  node_health = {
    for node in data.kubernetes_nodes.all.nodes : node.metadata[0].name => {
      ready           = anytrue([for c in node.status[0].conditions : c.type == "Ready" && c.status == "True"])
      kubelet_version = node.status[0].node_info[0].kubelet_version
      os_image        = node.status[0].node_info[0].os_image
    }
  }
}
