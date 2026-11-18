#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Entry point of the push-stage and manual pre-commit hooks
# (.pre-commit-config.yaml). Runs the same CI scripts as the pipeline, on the
# Terraform roots / projects affected by the files pre-commit passes (the
# pushed files, or every file with --all-files):
#
#   ci/scripts/pre-commit-hook.sh validate [files...]   # init (read-only lock) + validate
#   ci/scripts/pre-commit-hook.sh test     [files...]   # init + validate + terraform test
#   ci/scripts/pre-commit-hook.sh tflint   [files...]   # TFLint per affected project
#   ci/scripts/pre-commit-hook.sh trivy    [files...]   # Trivy HIGH/CRITICAL gate
#   ci/scripts/pre-commit-hook.sh checkov  [files...]   # Checkov project policies
#
# Root selection is ci.py's (same rules as CI change detection). Terraform is
# required; TFLint, Trivy and Checkov are optional locally: when one is not
# installed the check is reported as skipped (CI always runs it). No Azure
# credentials, backend or cluster are needed (init -backend=false, mocked tests).
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

check="${1:?usage: pre-commit-hook.sh validate|test|tflint|trivy|checkov [files...]}"
shift
scripts_dir="${CI_REPO_ROOT}/ci/scripts"
failed=0

projects() {
  local manifest
  for manifest in "${CI_REPO_ROOT}"/ci/projects/*.json; do basename "$manifest" .json; done
}

# Roots of a project affected by the given files (one per line).
affected_roots() {
  local project="$1"
  shift
  python3 "${scripts_dir}/ci.py" changes "$project" --files "$@" |
    python3 -c 'import json, sys; [print(r) for r in json.load(sys.stdin)["roots"]]' | tr -d '\r'
}

# The CLI pinned by the project (.terraform-version) is what CI uses; another
# version still has to satisfy required_version (terraform init enforces it).
warn_terraform_version() {
  local project="$1" pinned installed
  pinned="$(tr -d '[:space:]' <"${CI_REPO_ROOT}/${project}/.terraform-version")"
  installed="$(terraform version | head -1 | awk '{print $2}' | tr -d 'v\r')"
  if [[ "$installed" != "$pinned" ]]; then
    ci_warn "${project}: local Terraform ${installed} differs from the pinned ${pinned} (${project}/.terraform-version, used by CI)"
  fi
}

# Optional tool: skip with a visible message when it is not installed.
optional_tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  ci_warn "${1} is not installed: '${check}' skipped locally (CI runs it). Linux/WSL: ci/scripts/install-tools.sh ${1}"
  return 1
}

run() {
  if ! "$@"; then
    failed=$((failed + 1))
  fi
}

case "$check" in
  validate | test | tflint | trivy | checkov) ;;
  *) ci_die "unknown check '${check}' (validate|test|tflint|trivy|checkov)" ;;
esac
if [[ "$check" == "validate" || "$check" == "test" ]]; then
  ci_require terraform python3
else
  ci_require python3
fi

for project in $(projects); do
  mapfile -t roots < <(affected_roots "$project" "$@")
  [[ ${#roots[@]} -gt 0 ]] || continue

  case "$check" in
    validate | test)
      warn_terraform_version "$project"
      mode=validate
      [[ "$check" == "test" ]] && mode=root
      for root in "${roots[@]}"; do
        run bash "${scripts_dir}/terraform-checks.sh" "$project" "$mode" "$root"
      done
      ;;
    tflint)
      optional_tool tflint && run bash "${scripts_dir}/lint.sh" "$project" tflint
      ;;
    trivy | checkov)
      optional_tool "$check" && run bash "${scripts_dir}/security-scan.sh" "$project" "$check"
      ;;
  esac
done

if ((failed > 0)); then
  ci_error "${check}: ${failed} check(s) failed"
  exit 1
fi
