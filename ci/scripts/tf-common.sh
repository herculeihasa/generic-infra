#!/usr/bin/env bash
# shellcheck shell=bash
# -----------------------------------------------------------------------------
# Backend initialisation shared by tf-plan.sh and tf-apply.sh (sourced), so
# that plan and apply always use the same state.
#
#   platform azure: azurerm backend, Entra ID (OIDC in CI), storage account
#                   from <root>/backend.hcl or $TF_STATE_STORAGE_ACCOUNT
#   platform wsl:   local backend through tp-local/scripts/tf-init.sh
# -----------------------------------------------------------------------------

# tf_init_root <project> <root> <platform>
tf_init_root() {
  local project="$1" root="$2" platform="$3" dir
  dir="$(ci_project_dir "$project")/${root}"
  [[ -d "$dir" ]] || ci_die "${project}/${root} does not exist (environment not implemented yet?)"
  export TF_IN_AUTOMATION=1 CHECKPOINT_DISABLE=1 TF_INPUT=0

  case "$platform" in
    azure)
      azure_auth_preflight
      local backend_args=()
      if [[ -f "${dir}/backend.hcl" ]]; then
        backend_args=("-backend-config=backend.hcl")
      elif [[ -n "${TF_STATE_STORAGE_ACCOUNT:-}" ]]; then
        backend_args=("-backend-config=storage_account_name=${TF_STATE_STORAGE_ACCOUNT}")
      else
        ci_die "backend not configured for ${project}/${root}: commit ${root}/backend.hcl (terraform -chdir=${project}/bootstrap output -raw backend_hcl) or set the TF_STATE_STORAGE_ACCOUNT variable"
      fi
      ci_group "terraform init (${project}/${root}, azurerm backend)"
      terraform -chdir="$dir" init -input=false -lockfile=readonly "${backend_args[@]}" ||
        ci_die "init failed: check the Storage Blob Data role of the identity on the state container and the account name"
      ci_endgroup
      ;;
    wsl)
      ci_group "terraform init (${project}/${root}, local state)"
      bash "$(ci_project_dir "$project")/scripts/tf-init.sh" "$root" -lockfile=readonly ||
        ci_die "init failed for ${project}/${root}"
      ci_endgroup
      ;;
    *) ci_die "unknown platform '${platform}'" ;;
  esac
}

# Credentials are never read from files: in GitHub Actions they come from
# OIDC (ARM_USE_OIDC + IDs from environment variables); locally from `az login`.
azure_auth_preflight() {
  local missing=() v
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    for v in ARM_CLIENT_ID ARM_TENANT_ID ARM_SUBSCRIPTION_ID; do
      [[ -n "${!v:-}" ]] || missing+=("$v")
    done
    [[ ${#missing[@]} -eq 0 ]] ||
      ci_die "Azure authentication not configured: set ${missing[*]} as variables of the GitHub environment (AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_SUBSCRIPTION_ID)"
    [[ "${ARM_USE_OIDC:-}" == "true" ]] || ci_die "ARM_USE_OIDC must be true in CI (workload identity federation, no client secret)"
    [[ -z "${ARM_CLIENT_SECRET:-}" ]] || ci_warn "ARM_CLIENT_SECRET is set: prefer OIDC federation and remove the secret"
  else
    [[ -n "${ARM_SUBSCRIPTION_ID:-}" ]] ||
      ci_die "ARM_SUBSCRIPTION_ID is not set (az login, then: export ARM_SUBSCRIPTION_ID=\$(az account show --query id -o tsv))"
  fi
}
