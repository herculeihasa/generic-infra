terraform {
  # Local state: the cluster lives on this machine, so does its state.
  #
  # The state path is supplied at init time, OUTSIDE the repository:
  #
  #   ../../scripts/tf-init.sh environments/dev
  #   # => terraform init -backend-config="path=$HOME/.local/state/tp-local/environments-dev.tfstate"
  #
  # One state per machine, shared by interactive runs and the self-hosted CI
  # runner. A plain `terraform init` falls back to ./terraform.tfstate, which
  # is git-ignored but would be a SECOND, diverging state: always use the
  # script.
  backend "local" {}
}
