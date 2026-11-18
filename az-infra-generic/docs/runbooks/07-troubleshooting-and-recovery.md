# 07 Troubleshooting and recovery

| | |
|---|---|
| **Scope** | Failures of `az-infra-generic` operations, locally and in the pipeline |
| **Status** | Diagnostics and resolutions derived from the implementation and Azure/Terraform behaviour; none could be reproduced against Azure yet (**Pending external prerequisites**) |

Each issue lists **symptoms, causes, diagnostics, resolution, verification**
and, where relevant, **escalation**. Recovery procedures (R-xx) follow.

## General diagnostics

```bash
terraform version && terraform providers                       # versions in use
az account show -o table                                       # identity and subscription
az monitor activity-log list -g rg-azinfra-dev-frc --offset 2h --status Failed \
  --query "[].{time:eventTimestamp, operation:operationName.localizedValue, message:properties.statusMessage}" -o table
TF_LOG=DEBUG terraform plan 2> tf-debug.log                    # last resort
```

> [!WARNING]
> `TF_LOG=DEBUG` logs contain request payloads and may contain secrets: keep
> them local and delete them after analysis.

## T-01 `terraform init` fails

**Status:** Implemented (diagnosis derived from Terraform behaviour; not reproduced).

* **Symptoms:** `Failed to query available provider packages`,
  `Provider dependency changes detected`, `the cached package ... does not match`.
* **Causes:** no access to `registry.terraform.io`; lock file inconsistent
  with constraints (`-lockfile=readonly`); corrupted local cache.
* **Diagnostics:** `terraform init -backend=false` (isolates provider issues
  from backend issues); `git diff -- '*.terraform.lock.hcl'`.
* **Resolution:** restore network access (proxy: `HTTPS_PROXY`); if a
  constraint changed intentionally, regenerate the lock (08 SEC-04);
  remove `.terraform/providers` and re-run `init`.
* **Verification:** `terraform validate` succeeds.
* Backend-specific errors: T-03.

## T-02 Provider authentication errors

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

* **Symptoms:** `building account: ... subscription ID could not be determined`,
  `AADSTS700016`, `AADSTS70021: No matching federated identity record found`,
  `Azure authentication not configured` (pipeline).
* **Causes:** `ARM_SUBSCRIPTION_ID` missing; expired `az login`; wrong
  tenant; pipeline: environment variables missing or federated credential
  subject mismatch (`repo:<owner>/<repository>:environment:<name>`).
* **Diagnostics:**

  ```bash
  az account show -o table
  env | grep '^ARM_' | sed 's/=.*/=<set>/'          # names only
  az identity federated-credential list -g "<identities-rg>" --identity-name "<identity>" \
    --query "[].{name:name, subject:subject}" -o table
  ```

* **Resolution:** `az login --tenant <TENANT_ID>` and export
  `ARM_SUBSCRIPTION_ID` ([02 SETUP-04](02-prerequisites-and-setup.md#setup-04-authenticate-interactively-operator));
  pipeline: fix the variables or the federated credential subject
  ([06 CI-01](06-cicd-operations.md#ci-01-enable-the-azure-stages-one-time)).
* **Verification:** `terraform plan` gets past the provider configuration.

## T-03 Backend connectivity or authorization

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

* **Symptoms:** `AuthorizationPermissionMismatch`, `This request is not authorized to perform this operation`,
  `KeyBasedAuthenticationNotPermitted`, `no such host`.
* **Causes:** missing/propagating *Storage Blob Data* role; IP filtering;
  wrong account name; key-based auth attempted.
* **Diagnostics:**

  ```bash
  cat backend.hcl
  az storage account show -n "<account>" --query "{publicAccess:publicNetworkAccess, defaultAction:networkRuleSet.defaultAction}" -o table
  az role assignment list --scope "<container-id>" -o table
  ```

* **Resolution:** [03 §3](03-backend-and-state-management.md#3-common-backend-initialization-errors).
* **Verification:** `terraform state list` succeeds.

## T-04 State locked

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

* **Symptoms:** `Error acquiring the state lock ... state blob is already locked`.
* **Causes:** concurrent run; interrupted run (killed process, cancelled job).
* **Diagnostics:** the `Lock Info` (ID, Who, Created); `gh run list --workflow az-infra-generic.yml --status in_progress`.
* **Resolution:** wait for the running operation; otherwise
  [03 BS-10](03-backend-and-state-management.md#bs-10-release-a-stuck-state-lock).
* **Verification:** a new `terraform plan` acquires the lock.

## T-05 Resource naming conflicts

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

* **Symptoms:** `StorageAccountAlreadyTaken`; `A resource with the ID "..." already exists - to be managed via Terraform this resource needs to be imported`.
* **Causes:** global name collision (storage account); a resource created
  outside Terraform or left over from a lost state.
* **Diagnostics:** `az resource show --ids "<id from the error>"`; `terraform state list`.
* **Resolution:** storage: set `storage_account_name`. Existing resource:
  adopt it with an `import` block ([03 BS-13](03-backend-and-state-management.md#bs-13-move-adopt-or-forget-resources-in-state)),
  or delete it if it is an orphan (confirm first).
* **Verification:** `terraform plan` shows the resource as managed, without replacement.

## T-06 Azure permission errors

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

* **Symptoms:** `AuthorizationFailed ... does not have authorization to perform action 'Microsoft.Authorization/roleAssignments/write'`;
  `LinkedAuthorizationFailed ... 'Microsoft.Network/virtualNetworks/subnets/join/action'`.
* **Causes:** deploying identity lacks *Role Based Access Control
  Administrator* / *User Access Administrator*; Azure Policy denial.
* **Diagnostics:** `az role assignment list --assignee "<object-id>" --all -o table`;
  policy denials: `az monitor activity-log list -g rg-azinfra-dev-frc --offset 2h --query "[?contains(operationName.value, 'Microsoft.Authorization/policies')]" -o table`.
* **Resolution:** grant the roles of [02 §2](02-prerequisites-and-setup.md#2-required-azure-permissions); for policy denials adapt the configuration or request an exemption.
* **Escalation:** subscription owner / governance team for policy exemptions.

## T-07 AKS cluster provisioning fails

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

* **Symptoms:** apply fails on `module.aks.azurerm_kubernetes_cluster.this`
  (`QuotaExceeded`, `ZonalAllocationFailed`, `SkuNotAvailable`,
  `InvalidTemplateDeployment`), or the cluster is in `Failed` state.
* **Causes:** vCPU quota; VM size unavailable in a zone; subnet permission
  not propagated; policy; invalid network ranges overlapping peered networks.
* **Diagnostics:**

  ```bash
  az aks show -g rg-azinfra-dev-frc -n aks-azinfra-dev-frc --query "{state:provisioningState, power:powerState.code}" -o table
  az vm list-usage --location francecentral -o table | grep -i DDSv5
  az role assignment list --scope "$(terraform output -raw aks_nodes_subnet_id)" -o table
  ```

* **Resolution:** quota increase or other `vm_size`/`zones`
  ([02 SETUP-07](02-prerequisites-and-setup.md#setup-07-check-regional-capacity));
  wait for role propagation and re-apply; cluster in `Failed` state: R-03.
* **Verification:** `provisioningState` `Succeeded`, `terraform plan` without changes.
* **Escalation:** Azure support for allocation failures persisting across zones/sizes.

## T-08 Node pool provisioning fails

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

* **Symptoms:** apply fails on `azurerm_kubernetes_cluster_node_pool.this["<pool>"]`
  or the system pool; pods `Pending` with `Insufficient cpu`.
* **Causes:** quota; Spot capacity unavailable; ephemeral OS disk larger than
  the VM cache/temp disk; `max_count` reached.
* **Diagnostics:**

  ```bash
  az aks nodepool show -g rg-azinfra-dev-frc --cluster-name aks-azinfra-dev-frc -n "<pool>" \
    --query "{state:provisioningState, count:count, min:minCount, max:maxCount, size:vmSize}" -o table
  kubectl get events -A --sort-by=.lastTimestamp | tail -30
  kubectl describe pod "<pending-pod>" -n "<namespace>"
  ```

* **Resolution:** adjust `vm_size`, `max_count`, `zones`, or priority
  (`Spot` → `Regular`) in `terraform.tfvars`; check the `workload_node_pool`
  plan warning (system pool tainted, no User pool).
* **Verification:** pool `Succeeded`; pods scheduled.

## T-09 Networking issues

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

* **Symptoms:** pods cannot reach the internet or Azure services; nodes
  `NotReady`; `Invalid value for variable` on `network` at plan time.
* **Causes:** the node subnet has no default outbound access by design
  (`default_outbound_access_enabled = false`): egress relies on the cluster's
  standard load balancer; a route table or firewall added outside Terraform;
  CIDR overlap (rejected by validation).
* **Diagnostics:**

  ```bash
  az network vnet subnet show -g rg-azinfra-dev-frc --vnet-name vnet-azinfra-dev-frc -n snet-aks-nodes \
    --query "{prefix:addressPrefix, defaultOutbound:defaultOutboundAccess, routeTable:routeTable.id, nsg:networkSecurityGroup.id}" -o json
  az aks show -g rg-azinfra-dev-frc -n aks-azinfra-dev-frc --query networkProfile -o json
  kubectl run nettest --rm -it --image=mcr.microsoft.com/azure-cli -n default --restart=Never -- \
    bash -c "nslookup mcr.microsoft.com && curl -sI https://mcr.microsoft.com"
  ```

* **Resolution:** remove unmanaged route tables/NSGs blocking egress or codify
  them; keep `outbound_type = "loadBalancer"` unless a NAT gateway / firewall
  is provided (module inputs). Validation errors name the conflicting ranges.
* **Verification:** the test pod resolves and reaches `mcr.microsoft.com`.

## T-10 Kubernetes API access fails

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

* **Symptoms:** `kubectl` → `Forbidden`, `You must be logged in`,
  `Unable to connect to the server: dial tcp ... i/o timeout`.
* **Causes:** no Azure RBAC role / admin group; kubeconfig not converted for
  kubelogin; client IP outside `api_server_authorized_ip_ranges`; role
  propagation delay.
* **Diagnostics:**

  ```bash
  kubectl config current-context
  az aks show -g rg-azinfra-dev-frc -n aks-azinfra-dev-frc --query "apiServerAccessProfile.authorizedIpRanges" -o tsv
  az role assignment list --scope "$(terraform output -raw aks_id)" -o table
  curl -s https://ifconfig.me                                   # your egress IP
  ```

* **Resolution:** [04 AKS-07](04-aks-module-operations.md#aks-07-configure-kubernetes-access) and
  [AKS-08](04-aks-module-operations.md#aks-08-grant-or-revoke-kubernetes-access);
  add your egress IP to `api_server_authorized_ip_ranges` and apply.
* **Verification:** `kubectl get nodes`.

## T-11 No data in Container Insights

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

* **Symptoms:** empty Container Insights views; no rows in `ContainerLogV2`.
* **Causes:** missing data collection rule association; workspace in another
  region than the rule (`monitoring.data_collection_rule_location`); agent pods
  failing.
* **Diagnostics:**

  ```bash
  az monitor data-collection rule association list --resource "$(terraform output -raw aks_id)" -o table
  kubectl get pods -n kube-system | grep -i ama-logs
  ```

* **Resolution:** re-apply (the association is managed); align the rule
  location with the workspace region.
* **Verification:** rows appear in `KubePodInventory` within about 10 minutes.

## T-12 Pipeline failures

**Status:** Pending external prerequisites (derived from the implementation; not reproduced against Azure).

See [06 CI-09](06-cicd-operations.md#ci-09-investigate-a-failed-run) and
[docs/ci-cd.md §12](../../../docs/ci-cd.md#12-troubleshooting).

## R-01 Recover from a failed or partial apply

**Status:** Pending external prerequisites.

1. Do not re-run blindly. Read the error and the list of resources applied
   before it (`terraform state list`).
2. If the lock is still held: [03 BS-10](03-backend-and-state-management.md#bs-10-release-a-stuck-state-lock).
3. Fix the cause (T-xx), then `terraform plan -out=fix.tfplan`:
   * resources marked `tainted` will be **replaced**: acceptable for new
     resources; for the cluster, check R-03 first and use
     `terraform untaint 'module.aks.azurerm_kubernetes_cluster.this'` if the
     cluster recovered;
   * `already exists` errors: T-05 (import);
   * resources deleted outside Terraform are re-created.
4. Apply the reviewed plan; verify with [05 DEP-07](05-deployment-procedures.md#dep-07-verify-the-deployed-resources).

## R-02 Roll back a configuration change

**Status:** Implemented (process).

Terraform has no "undo": roll back by applying the previous configuration.

1. `git revert <commit>` on a branch, pull request, review the plan (it shows
   the changes back to the previous configuration).
2. Merge; the pipeline plans and waits for approval; apply.
3. Not reversible this way: Kubernetes minor upgrades, replaced resources
   (data lost), deleted node pools (re-created empty).

## R-03 AKS cluster in `Failed` state

**Status:** Pending external prerequisites.

```bash
az aks show -g rg-azinfra-dev-frc -n aks-azinfra-dev-frc --query "{state:provisioningState, power:powerState.code}" -o table
az aks update -g rg-azinfra-dev-frc -n aks-azinfra-dev-frc          # reconcile without changes
```

If the reconcile succeeds (`Succeeded`), run `terraform plan` (expect no
change, or untaint as in R-01). If it keeps failing, collect the activity log
(General diagnostics) and escalate to Azure support; replacing the cluster
(`terraform apply -replace='module.aks.azurerm_kubernetes_cluster.this'`)
destroys its workloads and is the last resort.

## R-04 Recover from lost or corrupted state

**Status:** Pending external prerequisites.

1. Restore a previous version ([03 BS-08](03-backend-and-state-management.md#bs-08-restore-a-previous-state-version))
   or the container ([BS-09](03-backend-and-state-management.md#bs-09-recover-a-deleted-state-container)).
2. If no usable version exists, rebuild the state by importing the existing
   resources with `import` blocks for every address of
   [01 §3.2](01-architecture.md#32-resources-of-the-dev-environment)
   (12 resources for dev), then `terraform plan` until it shows no change.
3. **Bootstrap state** (local file, never in the backend): restore the latest
   copy kept outside the state account, or re-import the state storage with
   [03 BS-11](03-backend-and-state-management.md#bs-11-store-back-up-and-recover-the-bootstrap-state)
   step 4. A bootstrap plan that wants to **create** the account or containers
   means the state is missing or does not match: stop and recover it first.
   A plan that wants to **replace** `module.state_storage.azurerm_storage_account.this`
   fails on `prevent_destroy`: revert the input, or follow
   [03 BS-15](03-backend-and-state-management.md#bs-15-upgrade-an-existing-bootstrap-state-to-the-storage-module)
   for a state created before the storage module.

## R-05 Rebuild the dev environment from scratch

**Status:** Pending external prerequisites.

1. Destroy ([05 DEP-10](05-deployment-procedures.md#dep-10-destroy-the-environment)),
   or delete `rg-azinfra-dev-frc` manually if the state is unusable and then
   reset the state (`terraform state rm` of every address, or push an empty
   state after backup).
2. Create again ([04 AKS-01](04-aks-module-operations.md#aks-01-create-the-cluster)).
3. Re-grant manual access assignments (namespace-scoped roles of AKS-08).

## References

* [03 Backend and state management](03-backend-and-state-management.md), [04 AKS module operations](04-aks-module-operations.md), [06 CI/CD operations](06-cicd-operations.md)
