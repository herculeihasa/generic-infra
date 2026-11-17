#!/usr/bin/env python3
"""CI helper: project manifests and change detection.

Standard library only, so it runs unchanged on GitHub-hosted runners, the
self-hosted WSL runner and developer machines.

    python3 ci/scripts/ci.py manifest <project> <key>
    python3 ci/scripts/ci.py changes <project> [--base SHA] [--head SHA] [--all]

`changes` prints a JSON object and, when $GITHUB_OUTPUT is set, also writes
`roots` (JSON list) and `run` (true/false) step outputs.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_DIR = REPO_ROOT / "ci" / "projects"

# Files shared by every project: changing them re-validates everything.
SHARED_PREFIXES = (
    "ci/",
    ".github/workflows/_terraform-",
    ".gitleaks.toml",
)


def load_manifest(project: str) -> dict:
    path = MANIFEST_DIR / f"{project}.json"
    if not path.is_file():
        raise SystemExit(f"error: unknown project '{project}' (no {path.relative_to(REPO_ROOT)})")
    return json.loads(path.read_text(encoding="utf-8"))


def changed_files(base: str, head: str) -> list[str]:
    """Files changed between the merge base of base..head and head."""
    out = subprocess.run(
        ["git", "diff", "--name-only", f"{base}...{head}"],
        cwd=REPO_ROOT, check=True, capture_output=True, text=True,
    ).stdout
    return [line.strip() for line in out.splitlines() if line.strip()]


def select_roots(manifest: dict, files: list[str], workflow_file: str | None = None) -> tuple[list[str], str]:
    """Roots to validate for a change set, with the reason."""
    project = manifest["project"]
    roots = manifest["roots"]
    prefix = f"{project}/"

    if any(f.startswith(SHARED_PREFIXES) for f in files):
        return roots, "shared CI configuration changed"
    if workflow_file and workflow_file in files:
        return roots, "project workflow changed"

    # Documentation does not change Terraform behaviour (security scans still
    # run on every change, independently of the selected roots).
    project_files = [f[len(prefix):] for f in files if f.startswith(prefix) and not f.endswith(".md")]
    if not project_files:
        if any(f.startswith(prefix) for f in files):
            return [], "documentation only"
        return [], "no change in the project"

    # Modules are consumed by the roots: a module change re-validates all.
    if any(f.startswith("modules/") for f in project_files):
        return roots, "module changed"

    selected: set[str] = set()
    for f in project_files:
        owners = [r for r in roots if f.startswith(f"{r}/")]
        if not owners:
            # Project-level file (.terraform-version, .tflint.hcl, scanner
            # configuration, ...) or a directory outside the known roots.
            return roots, f"project-level file changed ({f})"
        selected.update(owners)
    return [r for r in roots if r in selected], "roots changed"


def is_null_sha(sha: str | None) -> bool:
    return not sha or set(sha) == {"0"}


def cmd_manifest(args: argparse.Namespace) -> int:
    value = load_manifest(args.project).get(args.key)
    if value is None:
        raise SystemExit(f"error: key '{args.key}' not in manifest")
    print(json.dumps(value) if isinstance(value, (list, dict)) else value)
    return 0


def cmd_changes(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.project)
    if args.all or is_null_sha(args.base) or is_null_sha(args.head):
        roots, reason = manifest["roots"], "full validation requested"
    else:
        roots, reason = select_roots(manifest, changed_files(args.base, args.head), args.workflow_file)

    result = {"project": manifest["project"], "roots": roots, "run": bool(roots), "reason": reason}
    print(json.dumps(result))

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a", encoding="utf-8") as fh:
            fh.write(f"roots={json.dumps(roots)}\n")
            fh.write(f"run={'true' if roots else 'false'}\n")
            fh.write(f"reason={reason}\n")
    return 0


def evaluate_gate(needs: dict) -> tuple[bool, list[str]]:
    """Aggregate GitHub `needs` results: only success/skipped pass.

    The change-detection job must itself succeed: if it failed, the other
    jobs were skipped and a green gate would be meaningless.
    """
    problems = [f"{job}: {data.get('result')}" for job, data in sorted(needs.items())
                if data.get("result") not in ("success", "skipped")]
    if "changes" in needs and needs["changes"].get("result") != "success":
        problems.append("changes: change detection did not succeed")
    return (not problems), sorted(set(problems))


def cmd_gate(args: argparse.Namespace) -> int:
    needs = json.loads(os.environ.get(args.env_var) or "{}")
    if not needs:
        raise SystemExit(f"error: ${args.env_var} is empty")
    ok, problems = evaluate_gate(needs)
    for job, data in sorted(needs.items()):
        print(f"{job:<24} {data.get('result')}")
    if not ok:
        print("quality gate FAILED: " + "; ".join(problems), file=sys.stderr)
        return 1
    print("quality gate passed")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("manifest", help="print a value of ci/projects/<project>.json")
    p.add_argument("project")
    p.add_argument("key")
    p.set_defaults(func=cmd_manifest)

    p = sub.add_parser("changes", help="Terraform roots affected by a change set")
    p.add_argument("project")
    p.add_argument("--base")
    p.add_argument("--head")
    p.add_argument("--all", action="store_true", help="select every root")
    p.add_argument("--workflow-file", help="project caller workflow (its change re-validates everything)")
    p.set_defaults(func=cmd_changes)

    p = sub.add_parser("gate", help="fail unless every needed job succeeded or was skipped")
    p.add_argument("--env-var", default="NEEDS_JSON", help="environment variable holding toJSON(needs)")
    p.set_defaults(func=cmd_gate)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
