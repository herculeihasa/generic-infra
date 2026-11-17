# =============================================================================
# tp-local bootstrap (stage 1): MicroK8s cluster inside WSL Ubuntu
#
# Run from WSL Ubuntu (not Windows): the scripts call snap/microk8s locally.
#   sudo -v                                  # cache sudo credentials (install only)
#   ../scripts/tf-init.sh bootstrap
#   terraform plan -out=bootstrap.tfplan && terraform apply bootstrap.tfplan
#
# Stage 2 (../environments/dev) then manages Kubernetes and Helm resources
# through the exported kubeconfig.
# =============================================================================

module "microk8s" {
  source = "../modules/microk8s"

  channel              = var.microk8s_channel
  kubeconfig_path      = var.kubeconfig_path
  api_server_address   = var.api_server_address
  wait_timeout_seconds = var.wait_timeout_seconds
  uninstall_on_destroy = var.uninstall_on_destroy
}
