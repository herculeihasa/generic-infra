# 02 Prerequisites and initial setup

| | |
|---|---|
| **Scope** | Operator workstation and identities for `az-infra-generic` |
| **Status** | Tool installation: standard vendor procedures (not executed during development). Offline initialization: **Validated**. Azure authentication and permissions: **Pending external prerequisites** |
| **Related** | [01 Architecture](01-architecture.md), [project README §4-§5](../../README.md#4-azure-prerequisites) |

## 1. Required tools

| Tool | Version | Used for | Required |
|---|---|---|---|
| Terraform | **1.17.2** (exact, from `.terraform-version`) | All configurations | Yes |
| Azure CLI (`az`) | current release | Authentication, inspection, installing kubectl/kubelogin | Yes |
| kubectl + kubelogin | installed by `az aks install-cli` | Cluster access with Entra ID | To access the cluster |
| Git | any recent | Cloning, change management | Yes |
| Python 3 | ≥ 3.11 | Local run of the pipeline gates (`ci/scripts/run-local.sh`) | Optional |
| GitHub CLI (`gh`) | current | Pipeline operations from a terminal (06 CI/CD operations) | Optional |

The modules accept Terraform `>= 1.9.0, < 2.0.0`; the root configurations
require `~> 1.17`. Use exactly 1.17.2 to match CI and the lock files.

## SETUP-01 Install Terraform 1.17.2

**Status:** Implemented (vendor procedure). **Context:** workstation.

**PowerShell (Windows):**

```powershell
winget install --id Hashicorp.Terraform --version 1.17.2 --exact
terraform version
```

**bash (Ubuntu / WSL), signed HashiCorp repository:**

```bash
sudo apt-get update && sudo apt-get install -y gnupg curl lsb-release
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update
apt-cache madison terraform | grep 1.17.2          # exact package version, e.g. 1.17.2-1
sudo apt-get install -y "terraform=<package-version>" && sudo apt-mark hold terraform
```

Alternative: `tfenv install` / `tenv tf install` in `az-infra-generic/` reads
`.terraform-version`.

**Expected result:** `terraform version` prints `Terraform v1.17.2`.

## SETUP-02 Install the Azure CLI

**Status:** Implemented (vendor procedure). **Context:** workstation.

```powershell
# PowerShell (Windows)
winget install --id Microsoft.AzureCLI --exact
```

```bash
# bash (Ubuntu / WSL): Microsoft installation script (requires sudo)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
```

**Validation:** `az version` prints the CLI version without error.

## SETUP-03 Install kubectl and kubelogin

**Status:** Implemented (vendor procedure). **Context:** workstation.

```bash
sudo az aks install-cli        # Linux/WSL: installs into /usr/local/bin (elevated)
kubectl version --client
kubelogin --version
```

On Windows run `az aks install-cli` in PowerShell and add the printed
directories to `PATH`. kubelogin is required because the cluster disables
local accounts: every kubeconfig authenticates through Microsoft Entra ID.

## SETUP-04 Authenticate interactively (operator)

**Status:** Pending external prerequisites. **Context:** workstation, any directory.

```bash
az login --tenant "<TENANT_ID>"
az account set --subscription "<SUBSCRIPTION_ID>"
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
az account show --query "{subscription:name, id:id, tenant:tenantId, user:user.name}" -o table
```

```powershell
# PowerShell
az login --tenant "<TENANT_ID>"
az account set --subscription "<SUBSCRIPTION_ID>"
$env:ARM_SUBSCRIPTION_ID = (az account show --query id -o tsv)
```

**Why `ARM_SUBSCRIPTION_ID`:** azurerm requires a subscription for plan and
apply and the code never hardcodes one. With the Azure CLI session the tenant
and credentials are taken from `az`; nothing is written to the repository.

**Validation:** `az account show` displays the expected subscription and tenant.

## SETUP-05 Authenticate non-interactively (CI, automation)

**Status:** Pending external prerequisites. Used by the pipeline
(06 CI/CD operations). Terraform and the `azurerm`
backend read the same variables.

| Method | Variables | Recommendation |
|---|---|---|
| OIDC / workload identity federation | `ARM_USE_OIDC=true`, `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` | **Recommended** (no secret); implemented in the pipeline |
| Managed identity of a self-hosted runner | `ARM_USE_MSI=true`, `ARM_CLIENT_ID` (user-assigned), `ARM_SUBSCRIPTION_ID` | Acceptable |
| Service principal with secret | `ARM_CLIENT_ID`, `ARM_CLIENT_SECRET`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` | Discouraged; the pipeline warns when `ARM_CLIENT_SECRET` is set |

## 2. Required Azure permissions

| Activity | Scope | Roles |
|---|---|---|
| Bootstrap the backend ([03 BS-01](03-backend-and-state-management.md#bs-01-bootstrap-the-backend)) | Subscription | *Owner*, or *Contributor* + *User Access Administrator* (role assignments, management lock) |
| Deploy an environment | Subscription (creates the resource group) | *Contributor* + *Role Based Access Control Administrator* (the AKS module creates role assignments) |
| Read/write its state | Container `tfstate-<env>` | *Storage Blob Data Contributor* (granted by the bootstrap) |
| Plan only (pipeline plan identity) | Resource group(s) / subscription, container | *Reader*, *Azure Kubernetes Service Cluster User Role*, *Storage Blob Data Reader* |
| Use kubectl as administrator | AKS cluster | Membership of an admin group (`aks_admin_group_object_ids`) or *Azure Kubernetes Service RBAC Cluster Admin* |

**Check your effective roles:**

```bash
OBJECT_ID="$(az ad signed-in-user show --query id -o tsv)"
az role assignment list --assignee "$OBJECT_ID" --all \
  --query "[].{role:roleDefinitionName, scope:scope}" -o table
```

## SETUP-06 Register the Azure resource providers

**Status:** Pending external prerequisites. Needed only when the deploying
identity lacks `*/register/action` (otherwise Terraform registers the list in
`resource_providers_to_register` at start-up).

```bash
for rp in Microsoft.Storage Microsoft.Compute Microsoft.ContainerService Microsoft.Insights \
          Microsoft.ManagedIdentity Microsoft.Network Microsoft.OperationalInsights \
          Microsoft.OperationsManagement Microsoft.PolicyInsights; do
  az provider register --namespace "$rp"
done
az provider list --query "[?namespace=='Microsoft.ContainerService' || namespace=='Microsoft.PolicyInsights'].{rp:namespace, state:registrationState}" -o table
```

**Expected result:** every listed provider shows `Registered` (registration can
take several minutes). Then set `resource_providers_to_register = []` for
identities without registration rights.

## SETUP-07 Check regional capacity

**Status:** Pending external prerequisites. dev needs DDSv5 vCPUs in
`francecentral` (6 minimum, about 24 at full scale-out with surge upgrades)
and the VM sizes in every zone used by the pools (`1`, `2`, `3`).

```bash
az vm list-usage --location francecentral -o table | grep -i "DDSv5"
az vm list-skus --location francecentral --size Standard_D2ds_v5 \
  --query "[].{size:name, zones:locationInfo[0].zones, restrictions:restrictions[].reasonCode}" -o json
az vm list-skus --location francecentral --size Standard_D4ds_v5 \
  --query "[].{size:name, zones:locationInfo[0].zones, restrictions:restrictions[].reasonCode}" -o json
```

**Expected result:** enough free vCPUs, zones `1 2 3` listed, no restriction.
Otherwise request a quota increase or change `vm_size` / `zones` in
`environments/dev/terraform.tfvars`.

## 3. Environment variables reference

| Variable | Needed by | Sensitive | Notes |
|---|---|---|---|
| `ARM_SUBSCRIPTION_ID` | provider, backend | no (never committed) | Always required for plan/apply |
| `ARM_TENANT_ID` | CI, multi-tenant users | no | Inferred from `az login` locally |
| `ARM_CLIENT_ID` | CI identity | no | Client ID of the federated identity |
| `ARM_USE_OIDC` | CI | no | `true` in GitHub Actions |
| `ARM_CLIENT_SECRET` | service principal only | **yes** | Discouraged; never in files |
| `TF_STATE_STORAGE_ACCOUNT` | pipeline scripts | no | Alternative to a committed `backend.hcl` |
| `TF_PLUGIN_CACHE_DIR` | optional | no | Shared provider cache, faster `init` |

## SETUP-08 Initialize the configurations

**Status:** offline initialization **Validated**; backend initialization
pending ([03 BS-05](03-backend-and-state-management.md#bs-05-initialize-an-environment-against-the-backend)).

**Purpose:** download the locked providers and modules to validate and test
without Azure access. **Context:** repository root.

```bash
for root in bootstrap environments/dev modules/aks; do
  terraform -chdir="az-infra-generic/${root}" init -backend=false -input=false
done
terraform -chdir=az-infra-generic/environments/dev init -backend=false -lockfile=readonly
```

**Expected result:** `Terraform has been successfully initialized!`;
`azurerm v5.14.0` is installed from the lock file. `-lockfile=readonly`
fails if the lock file does not match the constraints, which is the check the
pipeline performs.

**Validation:**

```bash
terraform -chdir=az-infra-generic/environments/dev validate
terraform -chdir=az-infra-generic/environments/dev test
```

Expected: `Success! The configuration is valid.` and `2 passed, 0 failed`.

## SETUP-09 Verify the workstation

**Status:** Validated (offline part). **Context:** repository root, bash
(Linux, WSL or Git Bash).

```bash
terraform version                              # v1.17.2
az account show -o table                       # expected subscription (after SETUP-04)
ci/scripts/run-local.sh az-infra-generic       # same gates as the pipeline
```

`run-local.sh` reports `PASS` for formatting, init/validate/test of each root,
and the CI unit tests; scanners that are not installed are reported
`SKIPPED` (they run in CI; on Linux x86_64 install them with
`ci/scripts/install-tools.sh`).

## Troubleshooting

| Symptom | Resolution |
|---|---|
| `Error: building account: ... subscription ID could not be determined` | `export ARM_SUBSCRIPTION_ID=...` (SETUP-04) |
| `Unsupported Terraform Core version` | Install 1.17.2 (SETUP-01) |
| `MissingSubscriptionRegistration` | SETUP-06 |
| `AuthorizationFailed` on role assignments | Missing *RBAC Administrator* / *User Access Administrator* (§2) |
| kubectl prompts for a device login or fails with `exec: kubelogin not found` | SETUP-03, then 04 AKS module operations, AKS-07 |

More: 07 Troubleshooting and recovery.
