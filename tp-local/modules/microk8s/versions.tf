terraform {
  # terraform_data and destroy-time provisioners referencing self.input need
  # Terraform >= 1.4; cross-variable validations need >= 1.9.
  required_version = ">= 1.9.0, < 2.0.0"

  # No provider: everything runs through terraform_data + local-exec.
}
