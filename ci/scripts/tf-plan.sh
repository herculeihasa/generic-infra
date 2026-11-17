#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Stage 4: Terraform plan for one deployable root.
#
#   ci/scripts/tf-plan.sh <project> <root> <environment> <azure|wsl>
#
# Produces in .ci-reports/plan/<project>-<root>-<environment>/:
#   tfplan          saved plan (applied as-is after approval)
#   tfplan.txt      human-readable plan (sensitive values masked)
#   summary.md      change counts and destructive-change warning
#   plan-meta.json  commit, counts, destructive addresses (used by the apply guard)
# tfplan.json is only used inside the job (it can contain sensitive values).
#
# Azure plans run with -lock=false and a read-only identity: applying a saved
# plan fails if the state changed in between, so no lock is needed to plan.
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tf-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/tf-common.sh"

project="${1:?usage: tf-plan.sh <project> <root> <environment> <azure|wsl>}"
root="${2:?usage: tf-plan.sh <project> <root> <environment> <azure|wsl>}"
environment="${3:?usage: tf-plan.sh <project> <root> <environment> <azure|wsl>}"
platform="${4:?usage: tf-plan.sh <project> <root> <environment> <azure|wsl>}"

dir="$(ci_project_dir "$project")/${root}"
out="${CI_REPO_ROOT}/.ci-reports/plan/${project}-${root//\//-}-${environment}"
rm -rf "$out"
mkdir -p "$out"

tf_init_root "$project" "$root" "$platform"

lock_args=()
[[ "$platform" == "azure" ]] && lock_args=(-lock=false)

ci_group "terraform plan (${project}/${root}, ${environment})"
set +e
terraform -chdir="$dir" plan -input=false -detailed-exitcode -lock-timeout=5m "${lock_args[@]}" -out="${out}/tfplan"
rc=$?
set -e
ci_endgroup
case "$rc" in
  0 | 2) ;;
  *) ci_die "terraform plan failed for ${project}/${root} (exit ${rc})" ;;
esac

terraform -chdir="$dir" show -no-color "${out}/tfplan" >"${out}/tfplan.txt"
terraform -chdir="$dir" show -json "${out}/tfplan" >"${out}/tfplan.json"

python3 "${CI_REPO_ROOT}/ci/scripts/ci.py" plan-report "${out}/tfplan.json" \
  --title "${project}/${root} (${environment})" --summary "${out}/summary.md" --meta "${out}/plan-meta.json" \
  --project "$project" --root "$root" --environment "$environment"

# Plan-level policies on resolved values (stricter config per environment if present).
if command -v checkov >/dev/null 2>&1; then
  bash "${CI_REPO_ROOT}/ci/scripts/security-scan.sh" "$project" checkov-plan "${out}/tfplan.json" "$environment"
else
  ci_warn "checkov not installed: plan-level policy check skipped (mandatory in CI)"
  [[ -z "${GITHUB_ACTIONS:-}" ]] || ci_die "checkov is required in CI"
fi

# Keep the JSON plan (may contain sensitive values) out of the artifact.
rm -f "${out}/tfplan.json"
echo "plan-dir=${out}" >>"${GITHUB_OUTPUT:-/dev/null}"
