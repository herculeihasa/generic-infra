#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# One-time preparation of WSL Ubuntu for tp-local. Idempotent.
#
# Run INSIDE WSL Ubuntu, as root:
#   sudo tp-local/scripts/wsl/prepare-wsl.sh [--with-kubectl-helm]
#
# 1. Enables systemd (required by snapd/MicroK8s). If it had to be enabled,
#    the script stops: run `wsl --shutdown` from Windows, reopen Ubuntu and
#    run it again.
# 2. Installs base packages: snapd, curl, ca-certificates, gnupg, jq, unzip, git.
# 3. Installs Terraform (version from tp-local/.terraform-version) from the
#    signed HashiCorp APT repository.
# 4. Optionally installs kubectl and helm snaps (otherwise use
#    `microk8s kubectl` / `microk8s helm`).
#
# MicroK8s itself is NOT installed here: Terraform (tp-local/bootstrap) does it.
# -----------------------------------------------------------------------------
set -euo pipefail

log() { printf '[prepare-wsl] %s\n' "$*"; }
die() {
  printf '[prepare-wsl] ERROR: %s\n' "$*" >&2
  exit 1
}

with_kubectl_helm=false
for arg in "$@"; do
  case "$arg" in
    --with-kubectl-helm) with_kubectl_helm=true ;;
    -h | --help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *) die "unknown argument: $arg" ;;
  esac
done

[[ $EUID -eq 0 ]] || die "run with sudo: sudo $0 $*"
grep -qi microsoft /proc/version || log "warning: this does not look like WSL; continuing anyway"

# shellcheck source=/dev/null
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "Ubuntu is required (found ${ID:-unknown})."

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tf_version="$(tr -d '[:space:]' <"${script_dir}/../../.terraform-version")"

# --- 1. systemd ---------------------------------------------------------------
if [[ "$(tr -d '[:space:]' </proc/1/comm)" != "systemd" ]]; then
  log "enabling systemd in /etc/wsl.conf"
  touch /etc/wsl.conf
  if grep -q '^\[boot\]' /etc/wsl.conf; then
    if grep -q '^systemd=' /etc/wsl.conf; then
      sed -i 's/^systemd=.*/systemd=true/' /etc/wsl.conf
    else
      sed -i '/^\[boot\]/a systemd=true' /etc/wsl.conf
    fi
  else
    printf '\n[boot]\nsystemd=true\n' >>/etc/wsl.conf
  fi
  log "systemd enabled. Now, from Windows PowerShell: wsl --shutdown"
  log "then reopen Ubuntu and run this script again."
  exit 0
fi
log "systemd is running"

# --- 2. base packages ---------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  snapd curl ca-certificates gnupg jq unzip git >/dev/null
systemctl enable --now snapd.socket snapd.service >/dev/null
snap wait system seed.loaded
log "base packages installed"

# --- 3. Terraform (signed HashiCorp repository) -------------------------------
keyring=/usr/share/keyrings/hashicorp-archive-keyring.gpg
if [[ ! -f "$keyring" ]]; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o "$keyring"
fi
echo "deb [signed-by=${keyring}] https://apt.releases.hashicorp.com ${VERSION_CODENAME} main" \
  >/etc/apt/sources.list.d/hashicorp.list
apt-get update -qq
pkg_version="$(apt-cache madison terraform | awk -v v="$tf_version" '$3 ~ "^"v"-" { print $3; exit }')"
[[ -n "$pkg_version" ]] || die "terraform ${tf_version} not found in the HashiCorp repository."
apt-get install -y -qq --allow-downgrades "terraform=${pkg_version}" >/dev/null
apt-mark hold terraform >/dev/null
log "terraform $(terraform version | head -1 | awk '{print $2}') installed (held at ${tf_version})"

# --- 4. optional CLIs ---------------------------------------------------------
if [[ "$with_kubectl_helm" == "true" ]]; then
  snap list kubectl >/dev/null 2>&1 || snap install kubectl --classic
  snap list helm >/dev/null 2>&1 || snap install helm --classic
  log "kubectl and helm installed"
fi

log "done. Next (as your user, not root):"
log "  sudo -v && tp-local/scripts/tf-init.sh bootstrap"
log "  cd tp-local/bootstrap && terraform plan -out=bootstrap.tfplan && terraform apply bootstrap.tfplan"
