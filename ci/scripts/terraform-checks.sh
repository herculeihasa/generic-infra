#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Stage 1 gates: formatting, initialisation, lock-file consistency and
# validation. Same commands in CI and locally.
#
#   ci/scripts/terraform-checks.sh <project> fmt
#   ci/scripts/terraform-checks.sh <project> root <root>   # init + lock + validate
#
# Lock files: a root whose .terraform.lock.hcl is committed is initialised
# with -lockfile=readonly, so a lock file inconsistent with the provider
# constraints (or missing a provider) fails instead of being rewritten.
# Child modules have no lock file by design and use a normal init.
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

project="${1:?usage: terraform-checks.sh <project> fmt|root <root>}"
action="${2:?usage: terraform-checks.sh <project> fmt|root <root>}"
project_dir="$(ci_project_dir "$project")"
export TF_IN_AUTOMATION=1 CHECKPOINT_DISABLE=1 TF_INPUT=0

check_fmt() {
  ci_group "terraform fmt -check (${project})"
  if terraform -chdir="$project_dir" fmt -check -recursive -diff; then
    ci_summary "- ✅ \`terraform fmt\`: ${project}"
  else
    ci_summary "- ❌ \`terraform fmt\`: ${project} (run \`terraform fmt -recursive ${project}\`)"
    ci_endgroup
    ci_die "formatting differences in ${project}"
  fi
  ci_endgroup
}

check_root() {
  local root="$1" dir lock_mode=()
  dir="${project_dir}/${root}"
  [[ -d "$dir" ]] || ci_die "root ${project}/${root} does not exist"

  ci_group "terraform init (${project}/${root})"
  if git -C "$CI_REPO_ROOT" ls-files --error-unmatch "${project}/${root}/.terraform.lock.hcl" >/dev/null 2>&1; then
    lock_mode=(-lockfile=readonly)
    ci_log "committed lock file: verifying it with -lockfile=readonly"
  fi
  terraform -chdir="$dir" init -backend=false "${lock_mode[@]}" ||
    ci_die "init failed for ${project}/${root} (lock file inconsistent with constraints? run 'terraform providers lock' for all platforms)"
  ci_endgroup

  ci_group "terraform validate (${project}/${root})"
  terraform -chdir="$dir" validate || ci_die "validate failed for ${project}/${root}"
  ci_endgroup
  ci_summary "- ✅ init/validate: \`${project}/${root}\` (Terraform $(terraform version | head -1 | awk '{print $2}'))"
}

case "$action" in
  fmt) check_fmt ;;
  root) check_root "${3:?usage: terraform-checks.sh <project> root <root>}" ;;
  *) ci_die "unknown action '${action}'" ;;
esac
