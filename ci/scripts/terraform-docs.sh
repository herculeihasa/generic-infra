#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Generate, or check, the generated reference of every reusable module README
# (terraform-docs, configuration in /.terraform-docs.yml).
#
#   ci/scripts/terraform-docs.sh [--check] [files...]
#
# Modules: <project>/modules/<name>/ whose README.md contains the
# <!-- BEGIN_TF_DOCS --> marker. With files, only the modules containing one
# of them are processed. Only the text between the markers is rewritten.
# --check fails when a README is out of date (nothing is written).
#
# terraform-docs is provided by the pre-commit hook environment (pinned
# version in .pre-commit-config.yaml): run it as
#   pre-commit run terraform-docs --all-files
# -----------------------------------------------------------------------------
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mode=generate
if [[ "${1:-}" == "--check" ]]; then
  mode=check
  shift
fi
ci_require terraform-docs

mapfile -t modules < <(
  cd "$CI_REPO_ROOT" &&
    git ls-files '*/modules/*/README.md' | while read -r readme; do
      grep -q '<!-- BEGIN_TF_DOCS -->' "$readme" && dirname "$readme"
    done
)
[[ ${#modules[@]} -gt 0 ]] || ci_die "no module README with a <!-- BEGIN_TF_DOCS --> marker"

selected=()
for module in "${modules[@]}"; do
  if [[ $# -eq 0 ]]; then
    selected+=("$module")
    continue
  fi
  for file in "$@"; do
    if [[ "${file//\\//}" == "${module}/"* ]]; then
      selected+=("$module")
      break
    fi
  done
done

failed=0
for module in "${selected[@]}"; do
  args=(--config "${CI_REPO_ROOT}/.terraform-docs.yml")
  [[ "$mode" == "check" ]] && args+=(--output-check)
  if ! (cd "$CI_REPO_ROOT" && terraform-docs "${args[@]}" "$module" >/dev/null); then
    ci_error "${module}/README.md: generated reference is out of date (run: pre-commit run terraform-docs --all-files)"
    failed=$((failed + 1))
  fi
done
((failed == 0)) || exit 1
ci_log "terraform-docs (${mode}): ${#selected[@]} module(s)"
