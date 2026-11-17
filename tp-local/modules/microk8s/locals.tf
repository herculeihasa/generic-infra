locals {
  # Relative to the root configuration's working directory, so that it stays
  # valid in destroy-time provisioners even if the repository is moved.
  scripts_dir = "${path.module}/scripts"

  kubeconfig_path = pathexpand(var.kubeconfig_path)
  api_server_url  = "https://${var.api_server_address}:16443"
}
