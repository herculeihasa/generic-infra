#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Run the pipeline quality and security gates locally (WSL / Linux / Git Bash).
#
#   ci/scripts/run-local.sh <project> [--all-roots]
#
# Same scripts as GitHub Actions. Gates whose tool is not installed locally are
# reported as SKIPPED (in CI every gate is mandatory). Install the pinned tools
# with ci/scripts/install-tools.sh (Linux x86_64).
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

project="${1:?usage: run-local.sh <project>}"
ci_project_dir "$project" >/dev/null
scripts_dir="${CI_REPO_ROOT}/ci/scripts"

declare -a results=()
failed=0

gate() {
  local name="$1"
  shift
  if "$@"; then
    results+=("PASS     ${name}")
  else
    results+=("FAIL     ${name}")
    failed=$((failed + 1))
  fi
}

skip() { results+=("SKIPPED  $1 ($2 not installed)"); }

# Stage 1 -----------------------------------------------------------------------
gate "terraform fmt" bash "${scripts_dir}/terraform-checks.sh" "$project" fmt
while read -r root; do
  [[ -n "$root" ]] && gate "init/validate/test ${root}" bash "${scripts_dir}/terraform-checks.sh" "$project" root "$root"
done < <(ci_manifest_list "$project" roots)
gate "script tests" bash "${scripts_dir}/terraform-checks.sh" "$project" scripts

# Stage 2 -----------------------------------------------------------------------
if command -v tflint >/dev/null 2>&1; then gate "tflint" bash "${scripts_dir}/lint.sh" "$project" tflint; else skip "tflint" tflint; fi
if command -v shellcheck >/dev/null 2>&1; then
  gate "shellcheck ${project}" bash "${scripts_dir}/lint.sh" "$project" shell
  gate "shellcheck ci" bash "${scripts_dir}/lint.sh" ci shell
else
  skip "shellcheck" shellcheck
fi
if command -v actionlint >/dev/null 2>&1; then
  gate "actionlint + CI unit tests" bash "${scripts_dir}/lint.sh" repo workflows
else
  skip "actionlint" actionlint
  gate "CI unit tests" bash -c "cd '${CI_REPO_ROOT}' && python3 -m unittest discover -s ci/tests"
fi

# Stage 3 (security) is added by ci/scripts/security-scan.sh when present.
if [[ -x "${scripts_dir}/security-scan.sh" ]]; then
  for scanner in gitleaks trivy checkov; do
    if command -v "$scanner" >/dev/null 2>&1; then
      gate "$scanner" bash "${scripts_dir}/security-scan.sh" "$project" "$scanner"
    else
      skip "$scanner" "$scanner"
    fi
  done
fi

printf '\n=== %s: local gate results\n' "$project"
printf '  %s\n' "${results[@]}"
if ((failed > 0)); then
  echo "${failed} gate(s) FAILED"
  exit 1
fi
echo "all executed gates passed (skipped gates still run in CI)"
