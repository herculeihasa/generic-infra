terraform {
  # Root configuration: pinned to the toolchain the project is validated with.
  # The exact CLI version used locally/CI is set in ../../.terraform-version.
  required_version = "~> 1.17"

  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      # 3.x: version-suffixed resources (kubernetes_*_v1). Exact build pinned
      # in .terraform.lock.hcl.
      version = "~> 3.5"
    }
    helm = {
      source = "hashicorp/helm"
      # 3.x: plugin-framework syntax (kubernetes = {...}, set = [...]).
      version = "~> 3.3"
    }
  }
}
