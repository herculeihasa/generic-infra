# 08 Security and maintenance

| | |
|---|---|
| **Scope** | Recurring security and maintenance tasks of `az-infra-generic` |
| **Status** | Upgrade and scanning procedures **Implemented**; Azure-side tasks **Pending external prerequisites** |

## 1. Security model summary

| Asset | Protection (implemented) | Reference |
|---|---|---|
| Azure credentials | None stored: CLI session locally, OIDC federation in CI | [02 SETUP-04/05](02-prerequisites-and-setup.md#setup-05-authenticate-non-interactively-ci-automation) |
| Terraform state | Entra ID-only storage, container-scoped roles, versioning, soft delete, double encryption, delete lock | [03](03-backend-and-state-management.md) |
| Cluster access | Entra ID + Azure RBAC, local accounts disabled, optional authorized IP ranges / private cluster | [04 AKS-07/08](04-aks-module-operations.md#aks-08-grant-or-revoke-kubernetes-access) |
| Workloads | Workload Identity, Azure Policy add-on, Key Vault CSI driver, Image Cleaner, Cilium network policies | [04 §2](04-aks-module-operations.md#2-interface-summary) |
| Repository | Gitleaks, Trivy, Checkov, policy-as-code, SHA-pinned actions | [docs/ci-cd.md §5](../../../docs/ci-cd.md#5-security-policy) |

## SEC-01 Rotate credentials

**Status:** Pending external prerequisites.

| Credential | Exists? | Rotation |
|---|---|---|
| Pipeline secrets | No (OIDC) | Nothing to rotate; review federated credential subjects (SEC-08) |
| Service principal secret (if one was introduced) | Not by design | Replace by OIDC; otherwise `az ad app credential reset` and update the CI secret store |
| Storage account keys of the state account | Exist but unusable (Shared Key disabled) | Optional: `az storage account keys renew -g rg-azinfra-tfstate-frc -n <account> --key primary` (then `secondary`) |
| AKS cluster certificates | Managed by AKS | `az aks rotate-certs -g rg-azinfra-dev-frc -n aks-azinfra-dev-frc` (causes API downtime; refresh kubeconfigs afterwards with [04 AKS-07](04-aks-module-operations.md#aks-07-configure-kubernetes-access)) |
| User kubeconfigs | No secret (Entra ID tokens via kubelogin) | `kubelogin remove-tokens` to force re-authentication |

## SEC-02 Manage secrets and sensitive data

**Status:** Implemented.

* The repository holds **no secret**: `terraform.tfvars` and `backend.hcl` are
  non-sensitive; `.gitignore` excludes state, plans, `.env`, kubeconfigs.
* Sensitive data exists in: Terraform **state**, **plan files** (local and
  pipeline artifacts, 5-day retention), `TF_LOG` output, `terraform show -json`.
  Keep them out of tickets and chats; delete local copies.
* Application secrets belong in Azure Key Vault, consumed through the Key
  Vault CSI driver and Workload Identity (enabled by the module); Key Vault
  itself is not managed by this project (Not implemented).
* If a secret is committed: revoke/rotate it first, then clean the history
  ([docs/ci-cd.md §5](../../../docs/ci-cd.md#secret-exposure-procedure)).

## SEC-03 Upgrade Terraform

**Status:** Implemented (procedure).

1. Read the Terraform changelog between the current and target versions.
2. Update `.terraform-version` (CI and tfenv read it). Adjust
   `required_version` in `bootstrap/versions.tf` and
   `environments/dev/versions.tf` (`~> 1.17`) only for a new major/minor
   policy. Modules keep `>= 1.9.0, < 2.0.0` (raise `TERRAFORM_MIN_VERSION` in
   `ci/tool-versions.env` with it if the floor changes).
3. Locally: `ci/scripts/run-local.sh az-infra-generic` with the new version.
4. Pull request: the pipeline validates with the new version and with the
   minimum version.
5. After merge, everyone installs the new version (02 SETUP-01).

## SEC-04 Upgrade the azurerm provider

**Status:** Implemented (procedure); Dependabot opens weekly grouped pull
requests for the root configurations (`.github/dependabot.yml`).

```bash
cd az-infra-generic/environments/dev          # repeat for bootstrap
terraform init -upgrade -backend=false
terraform providers lock \
  -platform=windows_amd64 -platform=linux_amd64 \
  -platform=darwin_amd64 -platform=darwin_arm64
terraform validate && terraform test
git diff .terraform.lock.hcl
```

For a **major** version (6.x): read the upgrade guide, change the
constraints (`~> 6.x` in roots, `>= 6.x, < 7.0.0` in `modules/aks/versions.tf`),
run the tests, then review a real plan carefully (attribute renames,
defaults). Never merge a provider upgrade whose plan shows unexpected
replacements.

## SEC-05 Version the AKS module

**Status:** Implemented inside this repository; Planned for other
repositories. Inside this repository the module is consumed by relative
path (`../../modules/aks`): it always moves with its callers. For other
repositories (planned):

* tag releases `aks-module/vMAJOR.MINOR.PATCH` (semantic versioning: removed
  or renamed input, changed default with replacement impact → major; new
  optional input → minor; fix → patch);
* consumers pin `?ref=aks-module/v<version>` (see
  [04 §4](04-aks-module-operations.md#4-consuming-the-module-in-another-project));
* record changes in the pull request description until a changelog exists.

## SEC-06 Operate security scanning

**Status:** Implemented; first execution happens on the first GitHub run.

* Scanners run on every pull request and push, and weekly (schedule).
* Triage a finding: fix it, or accept it in `.checkov.yaml` (justified) /
  `.trivyignore.yaml` (justified, path-scoped, `expired_at`).
* **Expiry dates:** the current Trivy acceptances (`AVD-AZU-0041`,
  `AVD-AZU-0012`) expire on **2027-03-31**; after that date the pipeline
  fails until they are re-reviewed (fix, or renew with a new justification).
  `ci/tests/test_security_config.py` also fails on expired entries.
* Production plans use `.checkov-prod.yaml` (no dev acceptances for API
  exposure and SKU).

## SEC-07 Secure the state

**Status:** Pending external prerequisites (quarterly).

```bash
SA="<state-account>"
az storage account show -n "$SA" -g rg-azinfra-tfstate-frc \
  --query "{sharedKey:allowSharedKeyAccess, publicAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction, tls:minimumTlsVersion}" -o table
az lock list -g rg-azinfra-tfstate-frc -o table
az role assignment list --scope "$(az storage account show -n "$SA" --query id -o tsv)" --include-inherited \
  --query "[].{principal:principalName, type:principalType, role:roleDefinitionName, scope:scope}" -o table
```

Expected: Shared Key `False`, lock present, only the operator group and the
pipeline identities hold *Storage Blob Data* roles. Restrict network access
when runner IPs are known ([03 BS-04](03-backend-and-state-management.md#bs-04-restrict-network-access-to-the-state-account)).

## SEC-08 Review access

**Status:** Pending external prerequisites (quarterly).

| Scope | Command / place | Expected |
|---|---|---|
| Subscription | `az role assignment list --scope /subscriptions/<SUBSCRIPTION_ID> --query "[].{principal:principalName, role:roleDefinitionName}" -o table` | Deploy identities, operators; no stale principals |
| AKS cluster | `az role assignment list --scope "$(terraform -chdir=az-infra-generic/environments/dev output -raw aks_id)" --include-inherited -o table` | `cluster_admin["deployer"]` only while no admin group exists |
| Admin groups | `az ad group member list --group "<group-object-id>" --query "[].userPrincipalName" -o tsv` | Current administrators only |
| Federated credentials | `az identity federated-credential list -g <identities-rg> --identity-name <identity> -o table` | Subjects match the GitHub environments |
| GitHub | Settings → Environments (reviewers, branch rules), repository collaborators | Reviewers current; `main` only for apply environments |

After admin groups exist, set `grant_deployer_cluster_admin = false` (removes
the deployer's cluster-admin assignment).

## SEC-09 Detect and handle drift

**Status:** Pending external prerequisites.

* Automatic: weekly scheduled plan ([06 CI-08](06-cicd-operations.md#ci-08-drift-detection)).
* Manual: `terraform plan -detailed-exitcode` on `main` → exit code `2` means drift.

Handling: identify who changed what (`az monitor activity-log list -g rg-azinfra-dev-frc --offset 7d -o table`);
either **revert** (apply the configuration) or **codify** the change (pull
request) before the next apply. Expected non-drifting changes: node counts
(autoscaler) and patch versions (auto-upgrade) are not managed by Terraform.

## SEC-10 Keep Kubernetes within support

**Status:** Pending external prerequisites.
AKS supports a limited window of minor versions; patch upgrades are automatic.

```bash
az aks get-versions --location francecentral -o table
az aks show -g rg-azinfra-dev-frc -n aks-azinfra-dev-frc --query currentKubernetesVersion -o tsv
```

Plan a minor upgrade ([04 AKS-05](04-aks-module-operations.md#aks-05-upgrade-kubernetes))
well before the current minor leaves support.

## 2. Maintenance calendar

| Frequency | Task | Procedure |
|---|---|---|
| Weekly | Review the scheduled run: drift, security findings | SEC-09, SEC-06 |
| Weekly | Merge or close Dependabot pull requests | SEC-04 |
| Monthly | Check Kubernetes version support and AKS upgrade notifications | SEC-10 |
| Quarterly | Access review; state security check | SEC-08, SEC-07 |
| Quarterly | Update pinned CI tools (version + SHA-256 in `ci/tool-versions.env`) | [docs/ci-cd.md](../../../docs/ci-cd.md) |
| Before 2027-03-31 | Re-review expiring Trivy acceptances | SEC-06 |
| Yearly | Recovery drill: restore a state version in a test container; rebuild dev | [03 BS-08](03-backend-and-state-management.md#bs-08-restore-a-previous-state-version), 07 R-05 |

## References

* [docs/ci-cd.md](../../../docs/ci-cd.md), `.github/dependabot.yml`, `ci/tool-versions.env`
* [Project README §14 (known limitations)](../../README.md#14-known-limitations-and-pending-azure-dependent-validation)
