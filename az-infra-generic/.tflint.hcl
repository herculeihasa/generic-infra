# TFLint configuration shared by every configuration of the project.
#
#   tflint --init   --config "$(pwd)/.tflint.hcl"
#   tflint --recursive --config "$(pwd)/.tflint.hcl"
#
# NOTE: prepared but not executed in the initial implementation environment
# (see README, "Validation commands").

config {
  # Also lint the local modules called by the root configurations.
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
