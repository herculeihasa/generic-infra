#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Initialise a tp-local root configuration with its canonical LOCAL state path.
#
# Run in WSL Ubuntu, from anywhere:
#   tp-local/scripts/tf-init.sh bootstrap
#   tp-local/scripts/tf-init.sh environments/dev [-upgrade]
#
# State location: ${TP_LOCAL_STATE_DIR:-${XDG_STATE_HOME:-~/.local/state}/tp-local}
# One state per machine and root, outside any Git checkout, so interactive runs
# and a self-hosted CI runner (same Linux user) operate on the SAME state.
# -----------------------------------------------------------------------------
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <bootstrap|environments/dev> [terraform init args...]" >&2
  exit 64
}

[[ $# -ge 1 ]] || usage
root="$1"
shift

case "$root" in
  bootstrap | environments/dev) ;;
  *) echo "error: unknown root '$root'" >&2; usage ;;
esac

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state_dir="${TP_LOCAL_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tp-local}"
state_file="${state_dir}/${root//\//-}.tfstate"

mkdir -p "$state_dir"
chmod 700 "$state_dir"

echo "tf-init: root=${root} state=${state_file}"
terraform -chdir="${project_dir}/${root}" init -input=false \
  -backend-config="path=${state_file}" "$@"
