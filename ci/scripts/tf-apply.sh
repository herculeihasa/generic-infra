#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Stage 5: apply the REVIEWED saved plan of one deployable root.
#
#   ci/scripts/tf-apply.sh <project> <root> <environment> <azure|wsl> <plan-dir>
#
# Refuses (ci.py apply-guard) when: not on main, not a push/manual run, plan
# produced for another commit, or destructive plan without ALLOW_DESTROY=true.
# Terraform itself refuses a stale plan (state changed since the plan).
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=tf-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/tf-common.sh"

project="${1:?usage: tf-apply.sh <project> <root> <environment> <azure|wsl> <plan-dir>}"
root="${2:?usage: tf-apply.sh <project> <root> <environment> <azure|wsl> <plan-dir>}"
environment="${3:?usage: tf-apply.sh <project> <root> <environment> <azure|wsl> <plan-dir>}"
platform="${4:?usage: tf-apply.sh <project> <root> <environment> <azure|wsl> <plan-dir>}"
plan_dir="${5:?usage: tf-apply.sh <project> <root> <environment> <azure|wsl> <plan-dir>}"

[[ -f "${plan_dir}/tfplan" && -f "${plan_dir}/plan-meta.json" ]] || ci_die "reviewed plan not found in ${plan_dir}"

ci_group "apply guard"
python3 "${CI_REPO_ROOT}/ci/scripts/ci.py" apply-guard "${plan_dir}/plan-meta.json" || {
  ci_endgroup
  ci_die "apply refused by the guard"
}
ci_endgroup

tf_init_root "$project" "$root" "$platform"

dir="$(ci_project_dir "$project")/${root}"
ci_group "terraform apply (${project}/${root}, ${environment}, saved plan)"
terraform -chdir="$dir" apply -input=false -lock-timeout=10m "${plan_dir}/tfplan" ||
  ci_die "apply failed (a stale plan means the state changed after review: re-run the pipeline)"
ci_endgroup

ci_summary "### Applied: ${project}/${root} (${environment})"
ci_summary "Non-sensitive outputs:"
ci_summary '```'
terraform -chdir="$dir" output -json | python3 -c '
import json, sys
for name, o in sorted(json.load(sys.stdin).items()):
    value = "(sensitive)" if o.get("sensitive") else json.dumps(o.get("value"))
    print(name + " = " + value)
' | while IFS= read -r line; do ci_summary "$line"; done
ci_summary '```'
