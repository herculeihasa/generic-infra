#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Install the pinned CI tools (Linux x86_64) into ${CI_TOOLS_DIR}/bin.
#
#   ci/scripts/install-tools.sh tflint trivy gitleaks actionlint checkov
#
# Versions and SHA-256 come from ci/tool-versions.env. A download whose
# checksum does not match is rejected. Already-installed versions are reused
# (idempotent, cache-friendly). Terraform is installed separately
# (hashicorp/setup-terraform in CI, tfenv/apt locally).
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ci_load_tool_versions

[[ "$(uname -s)-$(uname -m)" == "Linux-x86_64" ]] ||
  ci_die "install-tools.sh supports Linux x86_64 only (CI runners, WSL). Install the tools manually elsewhere."
ci_require curl sha256sum tar unzip python3

mkdir -p "${CI_BIN_DIR}" "${CI_TOOLS_DIR}/versions"

installed_version() { cat "${CI_TOOLS_DIR}/versions/$1" 2>/dev/null || true; }

# download <url> <sha256> <dest>
download_verified() {
  local url="$1" sha="$2" dest="$3"
  curl -fsSL --retry 3 -o "$dest" "$url"
  if ! echo "${sha}  ${dest}" | sha256sum --check --status; then
    rm -f "$dest"
    ci_die "checksum mismatch for ${url} (expected ${sha}): refusing to install"
  fi
}

# install_archive <tool> <version> <url> <sha256> <binary-in-archive>
install_archive() {
  local tool="$1" version="$2" url="$3" sha="$4" member="$5" tmp
  if [[ "$(installed_version "$tool")" == "$version" && -x "${CI_BIN_DIR}/${tool}" ]]; then
    ci_log "${tool} ${version} already installed"
    return
  fi
  tmp="$(mktemp -d)"
  local archive="${tmp}/$(basename "$url")"
  download_verified "$url" "$sha" "$archive"
  case "$archive" in
    *.zip) unzip -q -o "$archive" "$member" -d "$tmp" ;;
    *.tar.gz) tar -xzf "$archive" -C "$tmp" "$member" ;;
  esac
  install -m 0755 "${tmp}/${member}" "${CI_BIN_DIR}/${tool}"
  echo "$version" >"${CI_TOOLS_DIR}/versions/${tool}"
  rm -rf "$tmp"
  ci_log "${tool} ${version} installed (sha256 verified)"
}

install_checkov() {
  local venv="${CI_TOOLS_DIR}/checkov-venv"
  if [[ "$(installed_version checkov)" == "$CHECKOV_VERSION" && -x "${venv}/bin/checkov" ]]; then
    ci_log "checkov ${CHECKOV_VERSION} already installed"
  else
    python3 -m venv "$venv"
    "${venv}/bin/pip" install --quiet --disable-pip-version-check "checkov==${CHECKOV_VERSION}"
    echo "$CHECKOV_VERSION" >"${CI_TOOLS_DIR}/versions/checkov"
    ci_log "checkov ${CHECKOV_VERSION} installed (isolated venv)"
  fi
  ln -sf "${venv}/bin/checkov" "${CI_BIN_DIR}/checkov"
}

[[ $# -gt 0 ]] || set -- tflint trivy gitleaks actionlint checkov

for tool in "$@"; do
  case "$tool" in
    tflint)
      install_archive tflint "$TFLINT_VERSION" \
        "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
        "$TFLINT_SHA256" tflint
      ;;
    trivy)
      install_archive trivy "$TRIVY_VERSION" \
        "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
        "$TRIVY_SHA256" trivy
      ;;
    gitleaks)
      install_archive gitleaks "$GITLEAKS_VERSION" \
        "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" \
        "$GITLEAKS_SHA256" gitleaks
      ;;
    actionlint)
      install_archive actionlint "$ACTIONLINT_VERSION" \
        "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz" \
        "$ACTIONLINT_SHA256" actionlint
      ;;
    checkov) install_checkov ;;
    *) ci_die "unknown tool '${tool}'" ;;
  esac
done

# Make the tools visible to the following steps of a GitHub Actions job.
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "${CI_BIN_DIR}" >>"$GITHUB_PATH"
fi
