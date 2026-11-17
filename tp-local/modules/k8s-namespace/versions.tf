terraform {
  required_version = ">= 1.9.0, < 2.0.0"

  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      # *_v1 resources and 3.x provider protocol.
      version = ">= 3.5.0, < 4.0.0"
    }
  }
}
