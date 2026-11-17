terraform {
  # Root configuration: pinned to the toolchain the project is validated with.
  # The exact CLI version used locally/CI is set in ../.terraform-version.
  required_version = "~> 1.17"

  # No provider on purpose. No Terraform provider manages snaps inside WSL,
  # so MicroK8s is installed and configured with the built-in terraform_data
  # resource and idempotent scripts (see ../modules/microk8s). Consequences:
  # - this root has no .terraform.lock.hcl (nothing to lock);
  # - `terraform plan` never touches the machine: every side effect happens
  #   at apply time, so the plan can run anywhere (including CI).

  # Local state, stored per machine OUTSIDE the repository. The path is set
  # at init time by ../scripts/tf-init.sh (~/.local/state/tp-local/...), so
  # interactive runs and a self-hosted CI runner share the same state.
  backend "local" {}
}
