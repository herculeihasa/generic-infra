# History rewrite: removal of the test suites (2026-11-18)

The test suites of this repository were removed from the working tree **and
from the entire Git history** of `main`. Every commit from the fourth one
onwards has a new hash. This page records what was rewritten, how, and what
each clone and fork must do.

## 1. What was removed

The 24 paths below were removed from every commit where they existed
(50 distinct file versions). No other path was touched.

| Paths | What they were |
|---|---|
| `az-infra-generic/bootstrap/tests/bootstrap.tftest.hcl`, `az-infra-generic/environments/dev/tests/dev.tftest.hcl` | `terraform test` suites of the Azure roots |
| `az-infra-generic/modules/aks/tests/{cluster,network,node_pools,outputs_access,security_observability}.tftest.hcl` | `terraform test` suites of the AKS module |
| `az-infra-generic/modules/storage_account/tests/{access,account,containers,security}.tftest.hcl` | `terraform test` suites of the Storage Account module |
| `tp-local/bootstrap/tests/bootstrap.tftest.hcl`, `tp-local/environments/dev/tests/dev.tftest.hcl` | `terraform test` suites of the tp-local roots |
| `tp-local/modules/k8s-namespace/tests/namespace.tftest.hcl`, `tp-local/modules/microk8s/tests/microk8s.tftest.hcl` | `terraform test` suites of the tp-local modules |
| `tp-local/modules/microk8s/scripts/tests/run.sh` | Behaviour tests of the microk8s scripts (stubbed commands) |
| `ci/tests/test_{azure_config,ci,docs,plan_apply,precommit,security_config,workflows}.py` | Python unit tests of `ci/scripts/ci.py` and repository policy tests |
| `ci/tests/__pycache__/test_ci.cpython-315.pyc` | Test bytecode committed once by mistake |

The repository policy rules of the former `test_docs.py`, `test_workflows.py`,
`test_security_config.py` and `test_precommit.py` were kept as a regular
checker, [`ci/scripts/check-repo.py`](../ci/scripts/check-repo.py), before the
rewrite. Operational checks were not tests and were kept:
`tp-local/scripts/host/Test-WslHost.ps1` (host prerequisites) and
`tp-local/scripts/verify-cluster.sh` (post-deployment verification).

## 2. Method

[git-filter-repo](https://github.com/newren/git-filter-repo) 2.47.0, run on
the maintainer's clone with the exact path list (no glob):

```bash
git filter-repo --force --invert-paths --paths-from-file history-rewrite-targets.txt
```

It was first run on a disposable clone and checked against a bundle of the
original history; the in-place run produced the same commit map.

| Item | Before | After |
|---|---|---|
| Branches | `main` | `main` (rewritten) |
| Tags | none | none |
| Commits | 64 (59 original + 5 cleanup commits) | 59 |
| Unchanged commits | — | the first three (`3624038`, `fa332e6`, `4ad3baa`) |
| First rewritten commit | `e7ede55` | `a5f001e` |
| Former `origin/main` | `a3e0a09` | `9558ab5` |
| Tree of the last commit | identical | identical |

Author, committer, dates and messages are unchanged. Five commits that only
touched removed files became empty and were dropped: `5ed6b70`, `bbd0fa4`,
`69b4b8d` and `d9c272a` (published), plus the local deletion commit of the
cleanup. The full old → new map is `.git/filter-repo/commit-map` in the
maintainer's clone, also kept with the backup.

**Not rewritten on purpose:** the historical *content* of shared files.
Workflows, `.pre-commit-config.yaml`, CI scripts and READMEs of older commits
still describe the test suites as they were then. Rewriting them would invent
states that never existed. As a consequence, the CI and pre-commit
configuration of a commit older than the cleanup refers to files that no
longer exist in that commit: check out old commits to read them, not to run
their pipeline.

## 3. Verification

Run in any clone of the rewritten history; every count must be `0`:

```bash
git log --all --no-renames --format= --name-only | grep -cE '(^|/)tests/|\.tftest\.hcl$'
git rev-list --all --objects | grep -cE ' (.+/)?tests/|\.tftest\.hcl$'
git log --all --oneline -S'mock_provider' | wc -l
```

On the maintainer's clone, the 50 removed file versions were also checked to
be absent from the object store (`git cat-file --batch-all-objects`), every
remaining commit was compared with its original (same tree minus the removed
paths, same metadata), and `git fsck --full` passed.

## 4. Backup

The original history (all refs, before any change) and the history just
before the rewrite are kept **outside the repository**, on the maintainer's
workstation, next to the working copy:
`../generic-infra-history-backup-2026-11-18/` (Git bundles, a mirror clone,
the path list, the commit map). The backup is not pushed anywhere. Recovery
procedure: `RECOVERY.md` in that directory.

## 5. Publishing the rewrite

The rewritten `main` diverges from the original one on GitHub, so it is
published by a force push, after an explicit decision of the repository
owner:

```bash
git remote add origin <repository URL>   # filter-repo removed the remote; see original-remotes.txt in the backup
git fetch origin
git push --force-with-lease=main:a3e0a095916f987b75652c39c8cf8954196ccd38 origin main
git branch --set-upstream-to=origin/main main
```

`--force-with-lease` refuses the push if `main` on GitHub is no longer
`a3e0a09` (somebody pushed in the meantime): fetch, inspect, decide again.
`git fetch origin` brings the old history back as `origin/main` until the
push replaces it; do **not** `git pull` or merge it.

After the push, also on GitHub:

* Required status checks of branch protection: the job
  `1 · init / validate / test (<root>)` is now `1 · init / validate (<root>)`,
  `1 · script tests` no longer exists, and the tp-local stage 5 is
  `5 · post-deployment verification (self-hosted)`. Update the rule if it
  names the old checks.
* Old commits stay reachable by their hash on GitHub (and in its caches)
  until GitHub garbage-collects them. Forks keep the old history. If the
  removed content must disappear completely, delete the forks and ask
  GitHub Support to purge the cached references, giving them the first
  changed commit (`e7ede55`).

## 6. What collaborators must do

The old and new histories share only their first three commits: never merge
one into the other.

| Situation | Action |
|---|---|
| No local work to keep (recommended) | Delete the clone and clone again |
| Clone without unpushed work | `git fetch origin && git checkout main && git reset --hard origin/main`, then `git reflog expire --expire=now --all && git gc --prune=now` |
| Local branch with unpushed commits | `git fetch origin`, then `git rebase --onto origin/main <old-base> <branch>` where `<old-base>` is the old commit the branch started from (new hash: commit map); drop any commit that only touched removed files |
| Fork | Delete it and fork again, or force-push the new `main` to it |
| Open pull request based on the old history | Close it and open a new one from a rebased branch |

Re-introducing a removed path (for example by merging an old branch) brings
the test files back: check that `git diff origin/main --stat` lists none of
the paths of §1 before pushing.
