#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Stage 3 gates: security and compliance. Reports go to .ci-reports/ (SARIF +
# text), uploaded as workflow artifacts.
#
#   ci/scripts/security-scan.sh <project> gitleaks   # secrets in Git history
#   ci/scripts/security-scan.sh <project> trivy      # misconfig, HIGH/CRITICAL fail
#   ci/scripts/security-scan.sh <project> checkov    # policies (built-in + custom)
#   ci/scripts/security-scan.sh repo checkov-workflows
#   ci/scripts/security-scan.sh <project> checkov-plan <tfplan.json>
#
# Failure conditions (docs/ci-cd.md §5):
#   gitleaks  any finding
#   trivy     any HIGH or CRITICAL misconfiguration not accepted in
#             <project>/.trivyignore.yaml (MEDIUM/LOW: reported, not blocking)
#   checkov   any failed check not accepted in the .checkov.yaml in use
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

target="${1:?usage: security-scan.sh <project>|repo <scanner>}"
scanner="${2:?usage: security-scan.sh <project>|repo <scanner>}"
reports="${CI_REPO_ROOT}/.ci-reports/${target}"
mkdir -p "$reports"

# Commit range for Gitleaks: only the new commits of a PR / push; the full
# history on manual and scheduled runs (and locally).
gitleaks_log_opts() {
  local event="${EVENT_NAME:-}" base="${BASE_SHA:-}" head="${HEAD_SHA:-}"
  if [[ "$event" == "pull_request" && -n "$base" && -n "$head" ]]; then
    echo "${base}..${head}"
  elif [[ "$event" == "push" && -n "$base" && "$base" != 0000000000000000000000000000000000000000 && -n "$head" ]]; then
    echo "${base}..${head}"
  fi
}

run_gitleaks() {
  local opts=() range
  ci_require gitleaks
  range="$(gitleaks_log_opts)"
  [[ -n "$range" ]] && opts+=("--log-opts=${range}")
  ci_group "gitleaks (${range:-full history})"
  if gitleaks git --config "${CI_REPO_ROOT}/.gitleaks.toml" --redact --no-banner --exit-code 1 \
    --report-format sarif --report-path "${reports}/gitleaks.sarif" "${opts[@]}" "$CI_REPO_ROOT"; then
    ci_summary "- ✅ Gitleaks: no secret (${range:-full history})"
  else
    ci_summary "- ❌ Gitleaks: secrets detected (see the gitleaks.sarif report; rotate any exposed credential)"
    ci_endgroup
    ci_die "Gitleaks detected secrets"
  fi
  ci_endgroup
}

run_trivy() {
  local project_dir ignorefile
  ci_require trivy
  project_dir="$(ci_project_dir "$target")"
  ignorefile="${project_dir}/.trivyignore.yaml"

  ci_group "trivy config: full report (all severities, not blocking)"
  trivy config --quiet --skip-dirs "**/.terraform" --ignorefile "$ignorefile" \
    --format sarif --output "${reports}/trivy.sarif" --exit-code 0 "$project_dir"
  trivy config --quiet --skip-dirs "**/.terraform" --ignorefile "$ignorefile" \
    --severity LOW,MEDIUM --format table --exit-code 0 "$project_dir" | tee "${reports}/trivy-low-medium.txt"
  ci_endgroup

  ci_group "trivy config: HIGH/CRITICAL gate"
  if trivy config --quiet --skip-dirs "**/.terraform" --ignorefile "$ignorefile" \
    --severity HIGH,CRITICAL --format table --exit-code 1 "$project_dir" | tee "${reports}/trivy-high-critical.txt"; then
    ci_summary "- ✅ Trivy: no HIGH/CRITICAL misconfiguration in ${target}"
  else
    ci_summary "- ❌ Trivy: HIGH/CRITICAL misconfigurations in ${target} (fix, or accept in ${target}/.trivyignore.yaml with a justification)"
    ci_endgroup
    ci_die "Trivy found HIGH/CRITICAL misconfigurations"
  fi
  ci_endgroup
}

# checkov_run <name> <checkov args...>
checkov_run() {
  local name="$1"
  shift
  ci_require checkov
  ci_group "checkov (${name})"
  if checkov "$@" --external-checks-dir "${CI_REPO_ROOT}/ci/policies/checkov" \
    --output cli --output sarif --output-file-path "console,${reports}/checkov-${name}.sarif"; then
    ci_summary "- ✅ Checkov: ${name}"
  else
    ci_summary "- ❌ Checkov: ${name} (fix, or accept the check in the .checkov.yaml in use with a justification)"
    ci_endgroup
    ci_die "Checkov reported failed checks (${name})"
  fi
  ci_endgroup
}

case "$scanner" in
  gitleaks) run_gitleaks ;;
  trivy) run_trivy ;;
  checkov)
    project_dir="$(ci_project_dir "$target")"
    checkov_run "$target" --directory "$project_dir" --config-file "${project_dir}/.checkov.yaml"
    ;;
  checkov-workflows)
    checkov_run workflows --directory "${CI_REPO_ROOT}/.github/workflows" --config-file "${CI_REPO_ROOT}/.checkov.yaml"
    ;;
  checkov-plan)
    plan_json="${3:?usage: security-scan.sh <project> checkov-plan <tfplan.json>}"
    project_dir="$(ci_project_dir "$target")"
    checkov_run "${target}-plan" --file "$plan_json" --framework terraform_plan \
      --config-file "${project_dir}/.checkov.yaml" --repo-root-for-plan-enrichment "$project_dir"
    ;;
  *) ci_die "unknown scanner '${scanner}'" ;;
esac
