#!/usr/bin/env python3
"""Repository policy checks (complement to actionlint, markdownlint and Checkov).

    python3 ci/scripts/check-repo.py                     # every group
    python3 ci/scripts/check-repo.py docs                # one group
    python3 ci/scripts/check-repo.py workflows security  # several groups

Groups:

docs        Runbooks (<project>/docs/runbooks/*.md) and, for links only, every
            Markdown document of the repository: relative links resolve and
            their #anchors match a heading; repository files quoted in `code`
            exist; code fences are closed and declare a language; headings do
            not skip levels and each runbook has one H1; table rows have as
            many cells as their header; Mermaid blocks use a known diagram
            type, quoted node labels and balanced blocks and brackets; each
            runbook index links every runbook of its directory; outputs, -var
            names, modules and resource addresses quoted in runbooks exist.
workflows   .github/workflows: top-level `permissions`; third-party actions
            pinned to a full commit SHA with a version comment; no ${{ }}
            expression inside `run:` scripts (values go through `env:`);
            checkout never persists credentials; `needs` and `if` only
            reference existing, direct dependencies; scripts invoked as
            ci/scripts/<name> exist and are executable in Git; self-hosted
            jobs only run on manual dispatch from main; applies only run from
            main on push or dispatch, through the approval environment; plans
            use the dedicated -plan environments; calls to local reusable
            workflows pass only declared inputs and all required ones.
security    Custom Checkov policies are well-formed and uniquely identified;
            Checkov configurations are explicit and only skip well-formed,
            justified check IDs; Trivy accepted findings are path-scoped,
            justified and carry a future expiry date; the Gitleaks
            configuration parses and extends the default rules.
precommit   .pre-commit-config.yaml: remote hook repositories pinned to a
            release tag or a commit SHA; tools shared with CI use the version
            of ci/tool-versions.env; additional dependencies are pinned; local
            hook scripts exist (and are executable in Git); expensive hooks
            never run at commit time; project hooks cover every ci/projects
            manifest; push hooks are installed by `pre-commit install`; the
            pinned pre-commit satisfies the minimum version; every reusable
            Terraform module README carries one generated-docs block.

The workflows, security and precommit groups need PyYAML (preinstalled on
GitHub-hosted runners, installed by the repo-policy pre-commit hook); without
it they are reported as skipped. The docs group uses the standard library only.

Exit status: 0 when every executed check passes, 1 when one fails, 2 on usage
errors.
"""

from __future__ import annotations

import datetime
import os
import re
import subprocess
import sys
import tomllib
from collections.abc import Callable, Iterator
from pathlib import Path

try:
    import yaml
except ImportError:
    yaml = None

REPO = Path(__file__).resolve().parents[2]
NEEDS_YAML = ("workflows", "security", "precommit")
CHECKS: dict[str, list[Callable[[], Iterator[str]]]] = {"docs": [], "workflows": [], "security": [], "precommit": []}


def check(group: str):
    """Register a generator of problem descriptions under a group."""
    def register(func: Callable[[], Iterator[str]]) -> Callable[[], Iterator[str]]:
        CHECKS[group].append(func)
        return func
    return register


def rel(path: Path) -> str:
    return path.relative_to(REPO).as_posix()


def git_modes(*paths: str) -> dict[str, str]:
    """Git file mode (100644, 100755) of the tracked files under the given paths."""
    out = subprocess.run(["git", "ls-files", "-s", "--", *paths], cwd=REPO,
                         capture_output=True, text=True, check=True).stdout
    return {line.split("\t", 1)[1]: line.split(" ", 1)[0] for line in out.splitlines()}


# =============================================================================
# docs
# =============================================================================
RUNBOOK_DIRS = sorted(REPO.glob("*/docs/runbooks"))
RUNBOOKS = sorted(p for d in RUNBOOK_DIRS for p in d.glob("*.md"))
ALL_DOCS = sorted(p for p in REPO.rglob("*.md")
                  if ".terraform" not in p.parts and ".git" not in p.parts and "node_modules" not in p.parts)

FENCE = re.compile(r"^(```+|~~~+)(.*)$")
FILE_REF = re.compile(r"`([A-Za-z0-9_.\-/]+\.(?:tf|sh|yml|yaml|hcl|json|ps1|py|md|example|env))`")
MERMAID_TYPES = ("flowchart", "graph", "sequenceDiagram", "stateDiagram-v2")


def slug(heading: str) -> str:
    """GitHub-style anchor of a heading."""
    text = re.sub(r"`", "", heading.strip().lower())
    text = re.sub(r"[^\w\- ]", "", text)
    return text.replace(" ", "-")


def split_blocks(text: str):
    """Yield (in_code, language, line_no, line) for every line."""
    in_code, lang = False, ""
    for i, line in enumerate(text.splitlines(), 1):
        m = FENCE.match(line.strip())
        if m:
            if not in_code:
                in_code, lang = True, m.group(2).strip()
                yield True, lang, i, line
                continue
            in_code = False
            yield True, lang, i, line
            continue
        yield in_code, lang, i, line


def prose_lines(text: str):
    return [(i, line) for in_code, _, i, line in split_blocks(text) if not in_code]


def headings(path: Path):
    return [(i, len(m.group(1)), m.group(2)) for i, line in prose_lines(path.read_text(encoding="utf-8"))
            if (m := re.match(r"^(#{1,6}) (.+)$", line))]


def mermaid_blocks(text: str):
    blocks, current = [], None
    for in_code, lang, i, line in split_blocks(text):
        if FENCE.match(line.strip()):
            if current is None and lang == "mermaid" and in_code:
                current = (i, [])
            elif current is not None:
                blocks.append(current)
                current = None
            continue
        if current is not None:
            current[1].append(line)
    return blocks


def table_cells(line: str) -> int:
    body = line.strip().strip("|")
    # Escaped pipes (\|) and pipes inside inline code do not split cells.
    body = re.sub(r"`[^`]*`", lambda m: m.group(0).replace("|", ""), body.replace("\\|", ""))
    return body.count("|") + 1


@check("docs")
def relative_links_and_anchors():
    for doc in ALL_DOCS:
        text = doc.read_text(encoding="utf-8")
        for i, line in prose_lines(text):
            for link in re.findall(r"\]\(([^)\s]+)\)", line):
                if re.match(r"^[a-z]+://", link) or link.startswith("mailto:"):
                    continue
                path, _, anchor = link.partition("#")
                target = (doc.parent / path).resolve() if path else doc
                if not target.exists():
                    yield f"{rel(doc)}:{i}: missing target {link}"
                    continue
                if anchor and target.suffix == ".md":
                    if anchor not in {slug(h) for _, _, h in headings(target)}:
                        yield f"{rel(doc)}:{i}: unknown anchor {link}"


@check("docs")
def code_fences_closed_and_typed():
    for doc in RUNBOOKS:
        opened = None
        for _, lang, i, line in split_blocks(doc.read_text(encoding="utf-8")):
            if FENCE.match(line.strip()):
                if opened is None:
                    opened = i
                    if not lang:
                        yield f"{rel(doc)}:{i}: code fence without language"
                else:
                    opened = None
        if opened is not None:
            yield f"{rel(doc)}:{opened}: unclosed code fence"


@check("docs")
def heading_hierarchy():
    for doc in RUNBOOKS:
        hs = headings(doc)
        if [lvl for _, lvl, _ in hs].count(1) != 1:
            yield f"{rel(doc)}: exactly one H1 expected"
        previous = 0
        for i, lvl, h in hs:
            if previous and lvl > previous + 1:
                yield f"{rel(doc)}:{i}: heading level jumps to H{lvl} ({h})"
            previous = lvl


@check("docs")
def tables_are_rectangular():
    for doc in RUNBOOKS:
        header = None
        for i, line in prose_lines(doc.read_text(encoding="utf-8")):
            if line.lstrip().startswith("|"):
                cells = table_cells(line)
                if header is None:
                    header = cells
                elif cells != header:
                    yield f"{rel(doc)}:{i}: {cells} cells, header has {header}"
            else:
                header = None


@check("docs")
def referenced_repository_files_exist():
    for doc in RUNBOOKS:
        project = doc.relative_to(REPO).parts[0]
        for i, line in prose_lines(doc.read_text(encoding="utf-8")):
            for ref in FILE_REF.findall(line):
                # Bare file names (`main.tf`) are relative to a directory
                # given in context; only paths are checked.
                if "/" not in ref or "<" in ref or ref.startswith(("~", "/")) or "*" in ref:
                    continue
                if not any((b / ref).exists() for b in (doc.parent, REPO / project, REPO)):
                    yield f"{rel(doc)}:{i}: `{ref}` not found"


@check("docs")
def terraform_references_match_the_code():
    """Outputs, -var names and resource addresses quoted in runbooks exist."""
    problems = set()
    for doc in RUNBOOKS:
        project = REPO / doc.relative_to(REPO).parts[0]
        tf_files = [p for p in project.rglob("*.tf") if ".terraform" not in p.parts]
        code = "\n".join(p.read_text(encoding="utf-8") for p in tf_files)
        root_outputs = set()
        for p in tf_files:
            if p.name == "outputs.tf" and "modules" not in p.relative_to(project).parts:
                root_outputs |= set(re.findall(r'^output "([^"]+)"', p.read_text(encoding="utf-8"), re.M))
        variables = set(re.findall(r'^variable "([^"]+)"', code, re.M))
        resources = set(re.findall(r'^resource "([^"]+)" "([^"]+)"', code, re.M))
        data = set(re.findall(r'^data "([^"]+)" "([^"]+)"', code, re.M))
        modules = set(re.findall(r'^module "([^"]+)"', code, re.M))
        text = doc.read_text(encoding="utf-8")
        where = rel(doc)
        for name in re.findall(r"terraform(?: -chdir=\S+)? output(?: -raw| -json)? ([a-z_][a-z0-9_]*)", text):
            if name not in root_outputs:
                problems.add(f"{where}: output '{name}' does not exist")
        if re.search(r"terraform(?: -chdir=\S+)? output(?: -raw| -json)? [a-z_][a-z0-9_]* [a-z_]", text):
            problems.add(f"{where}: `terraform output` takes a single output name")
        for name in re.findall(r"-var ['\"]([a-z_][a-z0-9_]*)=", text):
            if name not in variables:
                problems.add(f"{where}: -var '{name}' is not a declared variable")
        for mod in re.findall(r"\bmodule\.([a-z_][a-z0-9_]*)", text):
            if mod not in modules:
                problems.add(f"{where}: module '{mod}' does not exist")
        pattern = r"\b(data\.)?((?:azurerm|kubernetes|helm)_[a-z0-9_]+|terraform_data)\.([a-z_][a-z0-9_]*)\b"
        for is_data, rtype, rname in re.findall(pattern, text):
            if (rtype, rname) not in (data if is_data else resources):
                problems.add(f"{where}: {'data ' if is_data else ''}{rtype}.{rname} does not exist")
    yield from sorted(problems)


@check("docs")
def index_links_every_runbook():
    for d in RUNBOOK_DIRS:
        index = (d / "README.md").read_text(encoding="utf-8")
        for doc in sorted(d.glob("*.md")):
            if doc.name != "README.md" and f"({doc.name}" not in index:
                yield f"{rel(d)}/README.md does not link {doc.name}"


@check("docs")
def mermaid_blocks_are_well_formed():
    for doc in RUNBOOKS:
        for start, lines in mermaid_blocks(doc.read_text(encoding="utf-8")):
            where = f"{rel(doc)}:{start}"
            body = [l for l in lines if l.strip() and not l.strip().startswith("%%")]
            if not body or not body[0].strip().startswith(MERMAID_TYPES):
                yield f"{where}: unknown or missing diagram type"
                continue
            kind = body[0].split()[0]
            if kind in ("flowchart", "graph"):
                opened = sum(1 for l in body if re.match(r"^\s*subgraph\b", l))
                closed = sum(1 for l in body if l.strip() == "end")
                if opened != closed:
                    yield f"{where}: subgraph/end mismatch ({opened}/{closed})"
                for l in body[1:]:
                    unquoted = re.sub(r'"[^"]*"', '""', l)
                    for a, b in ("[]", "()", "{}"):
                        if unquoted.count(a) != unquoted.count(b):
                            yield f"{where}: unbalanced {a}{b} in: {l.strip()}"
                    if re.search(r'[\[({]\s*[^"\s\[({|>]', unquoted) and not re.match(r"^\s*(subgraph|classDef|class|style|linkStyle)\b", l):
                        yield f"{where}: unquoted node label in: {l.strip()}"
            if kind == "sequenceDiagram":
                opened = sum(1 for l in body if re.match(r"^\s*(alt|loop|opt|par|critical|rect)\b", l))
                closed = sum(1 for l in body if l.strip() == "end")
                if opened != closed:
                    yield f"{where}: block/end mismatch ({opened}/{closed})"


# =============================================================================
# workflows
# =============================================================================
WORKFLOW_DIR = REPO / ".github" / "workflows"
WORKFLOWS = sorted(WORKFLOW_DIR.glob("*.yml"))
SHA_PIN = re.compile(r"^[\w.-]+/[\w./-]+@[0-9a-f]{40}$")
DISPATCH = "github.event_name == 'workflow_dispatch'"
MAIN = "github.ref == 'refs/heads/main'"


def load_workflow(path: Path) -> dict:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    # PyYAML (YAML 1.1) reads the `on` key as boolean True.
    if True in data:
        data["on"] = data.pop(True)
    return data


def jobs(path: Path) -> dict:
    return load_workflow(path).get("jobs") or {}


def steps(workflow: dict):
    for job_id, job in (workflow.get("jobs") or {}).items():
        for step in job.get("steps") or []:
            yield job_id, step


def needs_list(job: dict) -> list[str]:
    needs = job.get("needs") or []
    return [needs] if isinstance(needs, str) else needs


@check("workflows")
def workflows_exist():
    if not WORKFLOWS:
        yield "no workflow found in .github/workflows"


@check("workflows")
def top_level_permissions():
    for wf in WORKFLOWS:
        if "permissions" not in load_workflow(wf):
            yield f"{wf.name}: missing top-level permissions"


@check("workflows")
def actions_pinned_by_sha_with_version_comment():
    for wf in WORKFLOWS:
        raw = wf.read_text(encoding="utf-8")
        for job_id, step in steps(load_workflow(wf)):
            uses = step.get("uses")
            if not uses or uses.startswith("./"):
                continue
            if not SHA_PIN.search(uses):
                yield f"{wf.name}/{job_id}: '{uses}' is not pinned to a commit SHA"
            if not re.search(re.escape(uses) + r" # v\d", raw):
                yield f"{wf.name}: '{uses}' lacks a '# vX' comment"


@check("workflows")
def no_expressions_in_run_scripts():
    for wf in WORKFLOWS:
        for job_id, step in steps(load_workflow(wf)):
            if "${{" in (step.get("run") or ""):
                yield f"{wf.name}/{job_id}/{step.get('name')}: use env: instead of ${{{{ }}}} in run"


@check("workflows")
def checkout_does_not_persist_credentials():
    for wf in WORKFLOWS:
        for job_id, step in steps(load_workflow(wf)):
            if str(step.get("uses", "")).startswith("actions/checkout@"):
                if (step.get("with") or {}).get("persist-credentials") is not False:
                    yield f"{wf.name}/{job_id}: checkout must set persist-credentials: false"


@check("workflows")
def needs_reference_existing_jobs():
    for wf in WORKFLOWS:
        all_jobs = jobs(wf)
        for job_id, job in all_jobs.items():
            for need in needs_list(job):
                if need not in all_jobs:
                    yield f"{wf.name}/{job_id}: needs unknown job '{need}'"


@check("workflows")
def referenced_ci_scripts_exist_and_are_executable():
    modes = git_modes("ci/scripts")
    for wf in WORKFLOWS:
        for job_id, step in steps(load_workflow(wf)):
            run = step.get("run") or ""
            for script in re.findall(r"(?:^|\s)(ci/scripts/[\w.-]+)", run):
                if not (REPO / script).is_file():
                    yield f"{wf.name}/{job_id}: {script} missing"
                elif (script.endswith(".sh") and not re.search(r"(python3|bash)\s+" + re.escape(script), run)
                      and modes.get(script) != "100755"):
                    yield f"{wf.name}/{job_id}: {script} must be executable in Git"


@check("workflows")
def self_hosted_jobs_only_run_on_manual_dispatch_from_main():
    for wf in WORKFLOWS:
        for job_id, job in jobs(wf).items():
            runs_on = job.get("runs-on")
            labels = runs_on if isinstance(runs_on, list) else [runs_on]
            if "self-hosted" in labels:
                condition = str(job.get("if", ""))
                for required in (DISPATCH, MAIN):
                    if required not in condition:
                        yield f"{wf.name}/{job_id}: self-hosted job without `{required}` in its if"


@check("workflows")
def if_conditions_only_use_direct_needs():
    # GitHub only exposes DIRECT dependencies in the `needs` context.
    for wf in WORKFLOWS:
        for job_id, job in jobs(wf).items():
            direct = needs_list(job)
            for ref in re.findall(r"needs\.([\w-]+)\.", str(job.get("if", ""))):
                if ref not in direct:
                    yield f"{wf.name}/{job_id}: `if` uses needs.{ref} which is not in needs"


@check("workflows")
def reusable_calls_on_self_hosted_runners_are_guarded():
    for wf in WORKFLOWS:
        for job_id, job in jobs(wf).items():
            if "self-hosted" in str((job.get("with") or {}).get("runner", "")):
                condition = str(job.get("if", ""))
                for required in (DISPATCH, MAIN):
                    if required not in condition:
                        yield f"{wf.name}/{job_id}: self-hosted call without `{required}` in its if"


@check("workflows")
def apply_only_from_main_on_push_or_dispatch():
    for wf in WORKFLOWS:
        for job_id, job in jobs(wf).items():
            if not str(job.get("uses", "")).endswith("_terraform-apply.yml"):
                continue
            condition = str(job.get("if", ""))
            if MAIN not in condition:
                yield f"{wf.name}/{job_id}: apply without `{MAIN}` in its if"
            if "pull_request" in condition:
                yield f"{wf.name}/{job_id}: apply must never run on pull requests"
            if "github.event_name == 'push'" not in condition and DISPATCH not in condition:
                yield f"{wf.name}/{job_id}: apply must be limited to push or workflow_dispatch"
            if job["with"]["github-environment"].endswith("-plan"):
                yield f"{wf.name}/{job_id}: apply must use the approval environment, not the plan one"


@check("workflows")
def plans_use_dedicated_plan_environments():
    for wf in WORKFLOWS:
        for job_id, job in jobs(wf).items():
            if str(job.get("uses", "")).endswith("_terraform-plan.yml"):
                if not job["with"]["github-environment"].endswith("-plan"):
                    yield f"{wf.name}/{job_id}: plan must use a dedicated '-plan' environment"


@check("workflows")
def apply_workflow_binds_environment_and_never_cancels():
    job = jobs(WORKFLOW_DIR / "_terraform-apply.yml")["apply"]
    if job.get("environment") != "${{ inputs.github-environment }}":
        yield "_terraform-apply.yml/apply: environment must be ${{ inputs.github-environment }}"
    if (job.get("concurrency") or {}).get("cancel-in-progress") is not False:
        yield "_terraform-apply.yml/apply: concurrency.cancel-in-progress must be false"


@check("workflows")
def reusable_workflow_calls_match_inputs():
    for wf in WORKFLOWS:
        for job_id, job in jobs(wf).items():
            uses = job.get("uses", "")
            if not uses.startswith("./.github/workflows/"):
                continue
            declared = load_workflow(REPO / uses[2:])["on"]["workflow_call"].get("inputs") or {}
            given = job.get("with") or {}
            for key in given:
                if key not in declared:
                    yield f"{wf.name}/{job_id}: unknown input '{key}' for {uses}"
            for key, spec in declared.items():
                if spec.get("required") and key not in given:
                    yield f"{wf.name}/{job_id}: missing required input '{key}' for {uses}"


# =============================================================================
# security
# =============================================================================
POLICIES = sorted((REPO / "ci" / "policies" / "checkov").glob("*.yaml"))
CHECKOV_CONFIGS = [REPO / ".checkov.yaml", *sorted(REPO.glob("*/.checkov*.yaml"))]
TRIVY_IGNORES = [REPO / "az-infra-generic" / ".trivyignore.yaml", REPO / "tp-local" / ".trivyignore.yaml"]
CATEGORIES = {"GENERAL_SECURITY", "LOGGING", "ENCRYPTION", "NETWORKING", "IAM", "BACKUP_AND_RECOVERY",
              "CONVENTION", "SECRETS", "KUBERNETES", "APPLICATION_SECURITY", "SUPPLY_CHAIN", "API_SECURITY"}
OPERATORS = {"equals", "not_equals", "exists", "not_exists", "contains", "not_contains", "within",
             "starting_with", "ending_with", "regex_match", "greater_than", "less_than"}


def conditions(definition: dict):
    if "cond_type" in definition:
        yield definition
    for key in ("and", "or"):
        for item in definition.get(key, []):
            yield from conditions(item)


@check("security")
def custom_policies_are_well_formed():
    if not POLICIES:
        yield "no custom Checkov policy in ci/policies/checkov"
    ids = []
    for path in POLICIES:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        meta = doc["metadata"]
        if not re.search(r"^CKV2_AZINFRA_\d+$", str(meta.get("id", ""))):
            yield f"{path.name}: id '{meta.get('id')}' must match CKV2_AZINFRA_<n>"
        if not meta.get("name"):
            yield f"{path.name}: name required"
        if meta.get("category") not in CATEGORIES:
            yield f"{path.name}: unknown category '{meta.get('category')}'"
        conds = list(conditions(doc["definition"]))
        if not conds:
            yield f"{path.name}: no condition"
        for cond in conds:
            if cond.get("cond_type") != "attribute":
                yield f"{path.name}: cond_type must be 'attribute'"
            if not cond.get("resource_types"):
                yield f"{path.name}: condition without resource_types"
            if not cond.get("attribute"):
                yield f"{path.name}: condition without attribute"
            if cond.get("operator") not in OPERATORS:
                yield f"{path.name}: unknown operator '{cond.get('operator')}'"
        ids.append(meta.get("id"))
    for duplicate in sorted({i for i in ids if ids.count(i) > 1}):
        yield f"duplicate custom policy ID {duplicate}"


@check("security")
def checkov_configs():
    for path in CHECKOV_CONFIGS:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        if not doc.get("framework"):
            yield f"{rel(path)}: framework must be explicit"
        elif "secrets" in doc["framework"]:
            yield f"{rel(path)}: secrets are Gitleaks' job"
        for skipped in doc.get("skip-check") or []:
            if not re.search(r"^CKV2?_[A-Z]+_\d+$", skipped):
                yield f"{rel(path)}: malformed check id {skipped}"


@check("security")
def every_skipped_check_is_justified():
    for path in CHECKOV_CONFIGS:
        lines = path.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            if re.match(r"^\s*-\s*CKV", line):
                previous = lines[i - 1].strip()
                if not (previous.startswith("#") or previous.startswith("- CKV")):
                    yield f"{rel(path)}:{i + 1}: skipped check without a justification comment"


@check("security")
def trivy_acceptances_are_justified_and_expire():
    today = datetime.date.today()
    for path in TRIVY_IGNORES:
        doc = yaml.safe_load(path.read_text(encoding="utf-8"))
        for entry in doc.get("misconfigurations") or []:
            where = f"{rel(path)}/{entry.get('id')}"
            if not re.search(r"^AVD-[A-Z]+-\d{4}$", str(entry.get("id", ""))):
                yield f"{where}: malformed finding id"
            if not entry.get("paths"):
                yield f"{where}: must be path-scoped"
            if len(entry.get("statement", "")) <= 20:
                yield f"{where}: justification (statement) required"
            expiry = entry.get("expired_at")
            if not isinstance(expiry, datetime.date):
                yield f"{where}: expired_at required"
            elif expiry <= today:
                yield f"{where}: acceptance expired on {expiry}, re-review it"
            for p in entry.get("paths") or []:
                if not (path.parent / p).exists():
                    yield f"{where}: path {p} does not exist"


@check("security")
def gitleaks_config():
    doc = tomllib.loads((REPO / ".gitleaks.toml").read_text(encoding="utf-8"))
    if not (doc.get("extend") or {}).get("useDefault"):
        yield ".gitleaks.toml: [extend] useDefault = true required"
    for allow in doc.get("allowlists", []):
        if not allow.get("description"):
            yield ".gitleaks.toml: allowlist without description"
        for pattern in allow.get("paths", []):
            try:
                re.compile(pattern)
            except re.error as exc:
                yield f".gitleaks.toml: invalid path pattern {pattern!r} ({exc})"


# =============================================================================
# precommit
# =============================================================================
PRECOMMIT_CONFIG = REPO / ".pre-commit-config.yaml"
RELEASE_TAG = re.compile(r"^v?\d+(\.\d+)+([.-][0-9A-Za-z]+)*$")
COMMIT_SHA = re.compile(r"^[0-9a-f]{40}$")
HEAVY_HOOKS = {"terraform-validate", "tflint", "trivy", "checkov", "repo-policy"}
PROJECT_HOOKS = ("terraform-validate", "tflint", "trivy", "checkov")
BEGIN, END = "<!-- BEGIN_TF_DOCS -->", "<!-- END_TF_DOCS -->"


def tool_versions() -> dict:
    values = {}
    for line in (REPO / "ci" / "tool-versions.env").read_text(encoding="utf-8").splitlines():
        if re.match(r"^[A-Z_]+=", line):
            key, _, value = line.partition("=")
            values[key] = value.strip()
    return values


def precommit() -> tuple[dict, list, dict]:
    config = yaml.safe_load(PRECOMMIT_CONFIG.read_text(encoding="utf-8"))
    repos = config["repos"]
    return config, repos, {h["id"]: h for r in repos for h in r["hooks"]}


@check("precommit")
def remote_repositories_are_pinned():
    _, repos, _ = precommit()
    for repo in repos:
        if repo["repo"] in ("local", "meta"):
            continue
        rev = str(repo.get("rev", ""))
        if not (RELEASE_TAG.match(rev) or COMMIT_SHA.match(rev)):
            yield f"{repo['repo']}: rev '{rev}' must be a release tag or a commit SHA"


@check("precommit")
def tools_shared_with_ci_use_the_ci_version():
    _, repos, _ = precommit()
    versions = tool_versions()
    for url_part, key in (("gitleaks/gitleaks", "GITLEAKS_VERSION"), ("rhysd/actionlint", "ACTIONLINT_VERSION")):
        matches = [r for r in repos if url_part in r["repo"]]
        if len(matches) != 1:
            yield f"expected one repository matching {url_part}, found {len(matches)}"
        elif matches[0]["rev"] != f"v{versions[key]}":
            yield f"{url_part}: rev {matches[0]['rev']} differs from {key}={versions[key]} (ci/tool-versions.env)"


@check("precommit")
def additional_dependencies_are_pinned():
    _, _, hooks = precommit()
    for hook_id, hook in hooks.items():
        for dep in hook.get("additional_dependencies", []):
            if not re.search(r"(==\d|@v\d)", dep):
                yield f"{hook_id}: dependency '{dep}' is not pinned"


@check("precommit")
def local_scripts_exist_and_are_executable():
    _, repos, _ = precommit()
    for repo in repos:
        if repo["repo"] != "local":
            continue
        for hook in repo["hooks"]:
            for token in str(hook["entry"]).split():
                if token.startswith("ci/") and token.endswith((".sh", ".py")):
                    if not (REPO / token).is_file():
                        yield f"{hook['id']}: {token} does not exist"
                    elif hook["language"] == "script" and git_modes(token).get(token) != "100755":
                        yield f"{hook['id']}: {token} is not executable in Git"


@check("precommit")
def heavy_hooks_do_not_run_at_commit_time():
    config, _, hooks = precommit()
    default_stages = config.get("default_stages", ["pre-commit"])
    for hook_id in sorted(HEAVY_HOOKS & set(hooks)):
        stages = hooks[hook_id].get("stages", default_stages)
        if "pre-commit" in stages:
            yield f"{hook_id} must not slow down commits"
        if "manual" not in stages:
            yield f"{hook_id} must be runnable with --hook-stage manual"


@check("precommit")
def project_hooks_cover_every_ci_project():
    # The file filters name the projects: a new ci/projects/<p>.json must be added there too.
    _, _, hooks = precommit()
    projects = sorted(p.stem for p in (REPO / "ci" / "projects").glob("*.json"))
    for hook_id in PROJECT_HOOKS:
        if hook_id not in hooks:
            yield f"{hook_id}: hook missing"
            continue
        pattern = re.compile(hooks[hook_id]["files"])
        for project in projects:
            if not pattern.search(f"{project}/environments/dev/main.tf"):
                yield f"{hook_id}: files filter does not cover project '{project}'"


@check("precommit")
def push_hooks_are_installed_by_default():
    config, _, _ = precommit()
    for hook_type in ("pre-commit", "pre-push"):
        if hook_type not in config.get("default_install_hook_types", []):
            yield f"default_install_hook_types must include {hook_type}"


@check("precommit")
def pinned_pre_commit_satisfies_the_minimum_version():
    config, _, _ = precommit()
    pinned = tuple(int(x) for x in tool_versions()["PRE_COMMIT_VERSION"].split("."))
    minimum = tuple(int(x) for x in str(config["minimum_pre_commit_version"]).split("."))
    if pinned < minimum:
        yield f"PRE_COMMIT_VERSION {pinned} is below minimum_pre_commit_version {minimum}"


@check("precommit")
def every_reusable_module_has_one_generated_docs_block():
    modules = sorted(p.parent for p in REPO.glob("*/modules/*/versions.tf"))
    if not modules:
        yield "no reusable module found (*/modules/*/versions.tf)"
    for module in modules:
        readme = module / "README.md"
        if not readme.is_file():
            yield f"{rel(module)}: README.md missing"
            continue
        text = readme.read_text(encoding="utf-8")
        if (text.count(BEGIN), text.count(END)) != (1, 1):
            yield f"{rel(module)}/README.md: one {BEGIN} / {END} pair expected"
        elif text.index(BEGIN) > text.index(END):
            yield f"{rel(module)}/README.md: markers out of order"


# =============================================================================
# runner
# =============================================================================
def main(argv: list[str]) -> int:
    groups = argv or list(CHECKS)
    unknown = [g for g in groups if g not in CHECKS]
    if unknown:
        print(f"usage: check-repo.py [{'|'.join(CHECKS)} ...] (unknown: {', '.join(unknown)})", file=sys.stderr)
        return 2
    annotate = bool(os.environ.get("GITHUB_ACTIONS"))
    passed = failed = skipped = 0
    for group in groups:
        if group in NEEDS_YAML and yaml is None:
            print(f"SKIP  {group}: PyYAML not installed (pip install PyYAML)")
            skipped += len(CHECKS[group])
            continue
        for func in CHECKS[group]:
            name = func.__name__.replace("_", " ")
            try:
                problems = list(func())
            except Exception as exc:  # a malformed file fails the check instead of aborting the run
                problems = [f"cannot evaluate: {type(exc).__name__}: {exc}"]
            if not problems:
                passed += 1
                print(f"ok    {group}: {name}")
                continue
            failed += 1
            print(f"FAIL  {group}: {name}")
            for problem in problems:
                print(f"::error::{group}: {problem}" if annotate else f"      {problem}")
    print(f"repository policy checks: {passed} passed, {failed} failed, {skipped} skipped")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
