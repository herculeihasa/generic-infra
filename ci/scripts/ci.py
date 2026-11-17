#!/usr/bin/env python3
"""CI helper: project manifests and change detection.

Standard library only, so it runs unchanged on GitHub-hosted runners, the
self-hosted WSL runner and developer machines.

    python3 ci/scripts/ci.py manifest <project> <key>
    python3 ci/scripts/ci.py changes <project> [--base SHA] [--head SHA] [--all]
    python3 ci/scripts/ci.py azure-config <project>
    python3 ci/scripts/ci.py gate            (reads $NEEDS_JSON)

`changes` prints a JSON object and, when $GITHUB_OUTPUT is set, also writes
`roots` (JSON list) and `run` (true/false) step outputs.
"""

from __future__ import annotations

import argparse
import json
import os
import re
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


GUID = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
FORBIDDEN_TF_PATTERNS = {
    "client_secret": r"^\s*client_secret\s*=",
    "client_certificate_password": r"^\s*client_certificate_password\s*=",
    "access_key": r"^\s*access_key\s*=",
    "sas_token": r"^\s*sas_token\s*=",
    "hardcoded subscription_id": rf'^\s*subscription_id\s*=\s*"{GUID}"',
    "hardcoded tenant_id": rf'^\s*tenant_id\s*=\s*"{GUID}"',
}


def strip_hcl_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"(#|//).*$", "", line) for line in text.splitlines())


def azure_config_problems(project: str, repo_root: Path = REPO_ROOT) -> list[str]:
    """Static Azure provider/backend checks (no credentials needed)."""
    manifest = load_manifest(project)
    project_dir = repo_root / project
    problems: list[str] = []

    for tf in sorted(project_dir.rglob("*.tf")):
        if ".terraform" in tf.parts:
            continue
        text = strip_hcl_comments(tf.read_text(encoding="utf-8"))
        for label, pattern in FORBIDDEN_TF_PATTERNS.items():
            if re.search(pattern, text, re.M):
                problems.append(f"{tf.relative_to(repo_root).as_posix()}: {label} must not be set in code")

    bootstrap_vars = strip_hcl_comments((project_dir / "bootstrap" / "variables.tf").read_text(encoding="utf-8"))
    env_block = re.search(r'variable "environments"\s*\{.*?default\s*=\s*\[(.*?)\]', bootstrap_vars, re.S)
    bootstrap_envs = set(re.findall(r'"([^"]+)"', env_block.group(1))) if env_block else set()

    for deployment in manifest.get("deployments", []):
        if deployment.get("platform") != "azure":
            continue
        root, env = deployment["root"], deployment["environment"]
        rel = f"{project}/{root}"
        backend_tf = project_dir / root / "backend.tf"
        if not backend_tf.is_file():
            problems.append(f"{rel}: backend.tf missing")
            continue
        backend = strip_hcl_comments(backend_tf.read_text(encoding="utf-8"))
        if not re.search(r'backend\s+"azurerm"', backend):
            problems.append(f"{rel}/backend.tf: azurerm backend required")
        if not re.search(r"use_azuread_auth\s*=\s*true", backend):
            problems.append(f"{rel}/backend.tf: use_azuread_auth = true required (Entra ID, no keys)")
        if not re.search(rf'container_name\s*=\s*"tfstate-{re.escape(env)}"', backend):
            problems.append(f'{rel}/backend.tf: container_name must be "tfstate-{env}" (per-environment isolation)')
        if not re.search(r'\bkey\s*=\s*"[^"]+\.tfstate"', backend):
            problems.append(f"{rel}/backend.tf: a state key ending in .tfstate is required")
        if re.search(r"storage_account_name\s*=", backend):
            problems.append(f"{rel}/backend.tf: storage_account_name belongs to backend.hcl (partial configuration)")

        backend_hcl = project_dir / root / "backend.hcl"
        if backend_hcl.is_file():
            keys = set(re.findall(r"^\s*([a-z_]+)\s*=", strip_hcl_comments(backend_hcl.read_text(encoding="utf-8")), re.M))
            if keys - {"storage_account_name"}:
                problems.append(f"{rel}/backend.hcl: only storage_account_name is allowed (found {sorted(keys)})")

        lock = project_dir / root / ".terraform.lock.hcl"
        lock_text = lock.read_text(encoding="utf-8") if lock.is_file() else ""
        provider = re.search(r'provider "registry\.terraform\.io/hashicorp/azurerm" \{(.*?)\n\}', lock_text, re.S)
        if not provider:
            problems.append(f"{rel}/.terraform.lock.hcl: hashicorp/azurerm must be locked")
        elif len(re.findall(r'"h1:', provider.group(1))) < 4:
            problems.append(f"{rel}/.terraform.lock.hcl: azurerm needs h1 hashes for windows/linux amd64 and darwin amd64/arm64")

        if env not in bootstrap_envs:
            problems.append(f"{project}/bootstrap: environments default does not create the tfstate-{env} container")
    return problems


def cmd_azure_config(args: argparse.Namespace) -> int:
    problems = azure_config_problems(args.project)
    for p in problems:
        print(f"::error::{p}" if os.environ.get("GITHUB_ACTIONS") else f"ERROR: {p}")
    if problems:
        return 1
    print(f"azure configuration checks passed for {args.project}")
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

    p = sub.add_parser("azure-config", help="static Azure provider and backend checks (no credentials)")
    p.add_argument("project")
    p.set_defaults(func=cmd_azure_config)

    p = sub.add_parser("gate", help="fail unless every needed job succeeded or was skipped")
    p.add_argument("--env-var", default="NEEDS_JSON", help="environment variable holding toJSON(needs)")
    p.set_defaults(func=cmd_gate)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
