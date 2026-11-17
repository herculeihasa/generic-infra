#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Stage 2 gates: static analysis.
#
#   ci/scripts/lint.sh <project> tflint      # TFLint, failure at severity >= warning
#   ci/scripts/lint.sh <project> shell       # ShellCheck on the project's scripts
#   ci/scripts/lint.sh repo workflows        # actionlint on .github/workflows + CI unit tests
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

target="${1:?usage: lint.sh <project>|repo <tflint|shell|workflows>}"
action="${2:?usage: lint.sh <project>|repo <tflint|shell|workflows>}"

run_tflint() {
  local project_dir config
  project_dir="$(ci_project_dir "$target")"
  config="${project_dir}/.tflint.hcl"
  [[ -f "$config" ]] || ci_die "missing ${target}/.tflint.hcl"
  ci_require tflint

  ci_group "tflint --init (${target})"
  # GITHUB_TOKEN (if set) avoids GitHub API rate limits for plugin downloads.
  (cd "$project_dir" && tflint --init --config "$config")
  ci_endgroup

  ci_group "tflint (${target})"
  if (cd "$project_dir" && tflint --recursive --config "$config" --minimum-failure-severity=warning --format=compact); then
    ci_summary "- ✅ TFLint: ${target}"
  else
    ci_summary "- ❌ TFLint: ${target}"
    ci_endgroup
    ci_die "TFLint reported issues in ${target}"
  fi
  ci_endgroup
}

run_shellcheck() {
  local files=()
  ci_require shellcheck
  mapfile -t files < <(git -C "$CI_REPO_ROOT" ls-files "${target}/*.sh" "${target}/**/*.sh")
  if [[ ${#files[@]} -eq 0 ]]; then
    ci_log "no shell script in ${target}"
    return
  fi
  ci_group "shellcheck (${target}: ${#files[@]} scripts)"
  # Severity >= warning fails; info/style findings are shown, not blocking.
  if (cd "$CI_REPO_ROOT" && shellcheck --external-sources --severity=warning "${files[@]}"); then
    ci_summary "- ✅ ShellCheck: ${target} (${#files[@]} scripts)"
  else
    ci_summary "- ❌ ShellCheck: ${target}"
    ci_endgroup
    ci_die "ShellCheck reported issues in ${target}"
  fi
  ci_endgroup
}

run_workflow_lint() {
  ci_require actionlint python3
  ci_group "actionlint (.github/workflows)"
  (cd "$CI_REPO_ROOT" && actionlint -color) || ci_die "actionlint reported issues"
  ci_endgroup
  ci_group "CI unit tests (ci/tests)"
  (cd "$CI_REPO_ROOT" && python3 -m unittest discover -s ci/tests) || ci_die "CI unit tests failed"
  ci_endgroup
  ci_summary "- ✅ actionlint + CI unit tests"
}

case "$action" in
  tflint) run_tflint ;;
  shell) run_shellcheck ;;
  workflows) run_workflow_lint ;;
  *) ci_die "unknown action '${action}'" ;;
esac
