# TFLint configuration shared by every configuration of tp-local.
#
#   tflint --init      --config "$(pwd)/.tflint.hcl"
#   tflint --recursive --config "$(pwd)/.tflint.hcl"
#
# There is no official ruleset for the kubernetes/helm providers: the
# terraform ruleset (recommended preset) covers language best practices.

config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
