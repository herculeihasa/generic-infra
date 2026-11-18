# Module `aks`

Generic, reusable Terraform module that provisions an Azure Kubernetes Service
(AKS) cluster with secure, production-oriented defaults:

* user-assigned control plane identity, Entra ID integration with Azure RBAC, no local accounts;
* Azure CNI Overlay powered by Cilium, optional bring-your-own subnets, private API server or authorized IP ranges;
* autoscaled, zone-redundant system pool dedicated to system pods, plus any number of User/System/Spot pools;
* Workload Identity, Azure Policy, Key Vault CSI driver, Image Cleaner; optional KMS, disk encryption set, Defender;
* opt-in Azure Monitor: Container Insights (managed identity + data collection rule) and control plane diagnostics.

The module creates the cluster and what belongs to it (identity, node pools,
monitoring wiring, role assignments). It never creates the resource group,
virtual network, Log Analytics workspace or Key Vault: the calling
configuration owns those and passes them in by ID.

## Usage

```hcl
module "aks" {
  source = "../../modules/aks"

  name                = "aks-demo-dev-frc"
  location            = "francecentral"
  resource_group_name = azurerm_resource_group.demo.name

  default_node_pool              = { vnet_subnet_id = azurerm_subnet.aks_nodes.id }
  network_contributor_subnet_ids = { nodes = azurerm_subnet.aks_nodes.id }
  node_pools                     = { apps = { vm_size = "Standard_D4ds_v5" } }

  entra_id_rbac = { admin_group_object_ids = ["<aks-admins-group-object-id>"] }
  monitoring    = { log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id }
}
```

Every input and output with its type, default and description:
[Reference (generated)](#reference-generated). Grouped explanations and more
examples: project [README §9](../../README.md#9-aks-module-inputs-and-outputs)
and [§10](../../README.md#10-usage-examples).

## Requirements

Terraform `>= 1.9.0, < 2.0.0` and `hashicorp/azurerm` `>= 5.14.0, < 6.0.0`
(details in the [generated reference](#reference-generated)). The module has
no provider block: configure `azurerm` in the root module.

## Files

| File | Content |
|---|---|
| `versions.tf` | Minimum Terraform / `azurerm` versions |
| `variables.tf` | Module interface: inputs, defaults, validations |
| `locals.tf` | Derived values |
| `identity.tf` | Control plane identity, subnet / cluster-admin / registry role assignments, admin access check |
| `main.tf` | AKS cluster |
| `node_pools.tf` | Additional node pools, workload capacity check |
| `monitoring.tf` | Container Insights data collection rule, control plane diagnostic settings |
| `outputs.tf` | Outputs |
| `tests/` | Offline `terraform test` suites using a mocked `azurerm` provider |

## Tests

```bash
terraform init -backend=false
terraform test   # 70 plan-mode runs, no Azure credentials needed
```

## Reference (generated)

Generated from the module code by [terraform-docs](https://terraform-docs.io/)
(configuration: `.terraform-docs.yml` at the repository root). Do not edit
between the markers: change the code, then run
`pre-commit run terraform-docs --all-files`.

<!-- BEGIN_TF_DOCS -->
### Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.9.0, < 2.0.0 |
| azurerm | >= 5.14.0, < 6.0.0 |

### Providers

| Name | Version |
| ---- | ------- |
| azurerm | >= 5.14.0, < 6.0.0 |

### Modules

No modules.

### Resources

| Name | Type |
| ---- | ---- |
| [azurerm_kubernetes_cluster.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_kubernetes_cluster_node_pool.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |
| [azurerm_monitor_data_collection_rule.container_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule) | resource |
| [azurerm_monitor_data_collection_rule_association.container_insights](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule_association) | resource |
| [azurerm_monitor_diagnostic_setting.cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |
| [azurerm_role_assignment.acr_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.cluster_admin](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.network_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |

### Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | Azure region of the cluster (e.g. francecentral). | `string` | n/a | yes |
| name | Name of the AKS cluster (1-63 characters: letters, digits, hyphens, underscores; must start and end with a letter or digit). | `string` | n/a | yes |
| resource\_group\_name | Existing resource group in which the cluster and its module-managed resources are created. | `string` | n/a | yes |
| api\_server\_authorized\_ip\_ranges | Public CIDR ranges allowed to reach a PUBLIC API server (e.g. office egress, CI runners). Empty = reachable from anywhere (still authenticated). Not supported with private\_cluster\_enabled. | `list(string)` | `[]` | no |
| auto\_scaler\_profile | Optional cluster autoscaler tuning shared by all autoscaled pools. Null keeps the AKS defaults. Durations use Go syntax (e.g. "10m"). | ```object({ balance_similar_node_groups = optional(bool) expander = optional(string) max_graceful_termination_sec = optional(number) max_node_provisioning_time = optional(string) scan_interval = optional(string) scale_down_delay_after_add = optional(string) scale_down_unneeded = optional(string) scale_down_utilization_threshold = optional(number) skip_nodes_with_local_storage = optional(bool) skip_nodes_with_system_pods = optional(bool) })``` | `null` | no |
| automatic\_upgrade\_channel | Cluster auto-upgrade channel: patch (recommended), stable, rapid, node-image, or null for no automatic Kubernetes upgrades. | `string` | `"patch"` | no |
| azure\_policy\_enabled | Install the Azure Policy add-on (Gatekeeper) to audit/enforce policy assignments on the cluster. Requires the Microsoft.PolicyInsights resource provider. | `bool` | `true` | no |
| cluster\_admin\_principal\_ids | Entra ID principals (static key => object ID of a user, group or service principal) granted "Azure Kubernetes Service RBAC Cluster Admin" on the cluster. Requires entra\_id\_rbac.azure\_rbac\_enabled. Prefer groups; for a first deployment, the deploying principal avoids being locked out. | `map(string)` | `{}` | no |
| container\_registry\_ids | Azure Container Registries (static key => registry ID) the kubelet identity may pull from (AcrPull role). Keys must be static strings so registries created in the same apply are supported. | `map(string)` | `{}` | no |
| default\_node\_pool | System node pool (Linux). Main settings: - vnet\_subnet\_id: node subnet (null = AKS-managed VNet); pod\_subnet\_id: dedicated pod subnet (vnet CNI mode only). - zones: availability zones (set [] in regions without zones). - auto\_scaling\_enabled with min\_count/max\_count, or a fixed node\_count. With autoscaling the pool   starts at min\_count and Terraform never fights the cluster autoscaler. - only\_critical\_addons\_enabled: taint the pool CriticalAddonsOnly=true:NoSchedule so it only runs   system pods (recommended; then declare at least one User pool in node\_pools). - os\_disk\_type: Managed or Ephemeral (Ephemeral needs a VM size whose cache/temp disk fits os\_disk\_size\_gb). - host\_encryption\_enabled: encryption at host (requires the EncryptionAtHost subscription feature). - temporary\_name\_for\_rotation: name used to rotate the pool when an immutable setting changes   (defaults to a generated name), so vm\_size/zones/disk changes do not recreate the cluster. | ```object({ name = optional(string, "system") vm_size = optional(string, "Standard_D4ds_v5") vnet_subnet_id = optional(string) pod_subnet_id = optional(string) zones = optional(list(string), ["1", "2", "3"]) auto_scaling_enabled = optional(bool, true) node_count = optional(number, 3) min_count = optional(number, 3) max_count = optional(number, 5) max_pods = optional(number) os_sku = optional(string, "AzureLinux") os_disk_type = optional(string, "Managed") os_disk_size_gb = optional(number, 128) only_critical_addons_enabled = optional(bool, true) host_encryption_enabled = optional(bool, false) orchestrator_version = optional(string) node_labels = optional(map(string), {}) temporary_name_for_rotation = optional(string) upgrade_settings = optional(object({ max_surge = optional(string, "10%") drain_timeout_in_minutes = optional(number) node_soak_duration_in_minutes = optional(number) }), {}) tags = optional(map(string), {}) })``` | `{}` | no |
| disk\_encryption\_set\_id | Optional Disk Encryption Set (customer-managed keys) for node OS and data disks. Forces a new cluster when changed. | `string` | `null` | no |
| dns\_prefix | DNS prefix of the API server FQDN. Defaults to a sanitised version of the cluster name. Forces a new cluster when changed. | `string` | `null` | no |
| entra\_id\_rbac | AKS-managed Microsoft Entra ID integration. azure\_rbac\_enabled = true authorises Kubernetes access with Azure role assignments; admin\_group\_object\_ids get cluster-admin. tenant\_id defaults to the provider's tenant. Null disables the integration (only possible with local accounts enabled). | ```object({ azure_rbac_enabled = optional(bool, true) admin_group_object_ids = optional(list(string), []) tenant_id = optional(string) })``` | `{}` | no |
| identity\_type | Control plane managed identity: UserAssigned (recommended: its principal exists before the cluster, so network/DNS permissions can be granted first) or SystemAssigned. | `string` | `"UserAssigned"` | no |
| image\_cleaner\_enabled | Run Image Cleaner (Eraser) to remove unused, potentially vulnerable images from nodes. | `bool` | `true` | no |
| image\_cleaner\_interval\_hours | Image Cleaner scan interval in hours (24-2160). | `number` | `168` | no |
| key\_management\_service | Optional KMS etcd encryption of Kubernetes secrets with a Key Vault key. Requires identity\_type = UserAssigned and, BEFORE the cluster is created, the control plane identity must hold "Key Vault Crypto User" on the key (bring the identity through user\_assigned\_identity). key\_vault\_id is required for a versionless key (automatic rotation) or a private vault. | ```object({ key_vault_key_id = string key_vault_network_access = optional(string, "Public") key_vault_id = optional(string) })``` | `null` | no |
| key\_vault\_secrets\_provider | Azure Key Vault Secrets Store CSI driver add-on: mounts Key Vault secrets/certificates into pods (authorise it with Workload Identity or the add-on identity exposed in outputs). | ```object({ enabled = optional(bool, true) secret_rotation_enabled = optional(bool, true) secret_rotation_interval = optional(string, "2m") })``` | `{}` | no |
| kubernetes\_version | Kubernetes version of the control plane. Null = AKS default at creation. With automatic\_upgrade\_channel = "patch" use MAJOR.MINOR (e.g. "1.33"); with "stable"/"rapid" leave null, since AKS then moves the minor version itself. | `string` | `null` | no |
| local\_account\_disabled | Disable the static local admin kubeconfig so every access goes through Microsoft Entra ID (recommended). Requires entra\_id\_rbac. | `bool` | `true` | no |
| maintenance\_windows | Planned maintenance windows. `auto_upgrade` constrains cluster auto-upgrades, `node_os` constrains node OS image updates. A null window means "any time". Each window: frequency (Daily \| Weekly \| AbsoluteMonthly \| RelativeMonthly), interval, duration in hours (4-24), day\_of\_week (Weekly, RelativeMonthly), day\_of\_month (AbsoluteMonthly), week\_index (RelativeMonthly: First..Last), start\_time ("HH:mm"), utc\_offset ("+01:00"), not\_allowed periods (RFC3339). | ```object({ auto_upgrade = optional(object({ frequency = string interval = optional(number, 1) duration = optional(number, 4) day_of_week = optional(string) day_of_month = optional(number) week_index = optional(string) start_time = optional(string) utc_offset = optional(string) not_allowed = optional(list(object({ start = string, end = string })), []) })) node_os = optional(object({ frequency = string interval = optional(number, 1) duration = optional(number, 4) day_of_week = optional(string) day_of_month = optional(number) week_index = optional(string) start_time = optional(string) utc_offset = optional(string) not_allowed = optional(list(object({ start = string, end = string })), []) })) })``` | `{}` | no |
| microsoft\_defender\_enabled | Enable the Microsoft Defender for Containers sensor (runtime threat detection; billed by Defender for Cloud). Sends its data to monitoring.log\_analytics\_workspace\_id. | `bool` | `false` | no |
| monitoring | Azure Monitor integration. Null disables it. log\_analytics\_workspace\_id is required. - container\_insights\_enabled: Container Insights agent with managed identity authentication,   wired through a data collection rule (DCR) and its association to the cluster. - container\_insights\_streams / data\_collection\_interval / namespace\_filtering\_mode (Off \| Include \| Exclude)   / namespaces: Container Insights collection scope (cost control). - data\_collection\_rule\_location: region of the Container Insights data collection rule; it must be the   region of the Log Analytics workspace (defaults to the cluster region). - diagnostic\_settings\_enabled: control plane logs (resource-specific tables) and metrics to the workspace;   diagnostic\_log\_categories selects the log categories (kube-audit is very verbose: prefer kube-audit-admin). | ```object({ log_analytics_workspace_id = string container_insights_enabled = optional(bool, true) container_insights_streams = optional(list(string), [ "Microsoft-ContainerLog", "Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory", "Microsoft-KubeNodeInventory", "Microsoft-KubePVInventory", "Microsoft-KubeServices", "Microsoft-KubeMonAgentEvents", "Microsoft-InsightsMetrics", "Microsoft-ContainerInventory", "Microsoft-ContainerNodeInventory", "Microsoft-Perf", ]) data_collection_rule_location = optional(string) data_collection_interval = optional(string, "1m") namespace_filtering_mode = optional(string, "Off") namespaces = optional(list(string), []) diagnostic_settings_enabled = optional(bool, true) diagnostic_log_categories = optional(list(string), [ "kube-apiserver", "kube-audit-admin", "kube-controller-manager", "kube-scheduler", "cluster-autoscaler", "guard", ]) diagnostic_metrics_enabled = optional(bool, true) })``` | `null` | no |
| network | Azure CNI configuration (the network plugin is always `azure`). - cni\_mode: "overlay" (recommended; pods get IPs from pod\_cidr, VNet IPs are only used by nodes)   or "vnet" (pods get VNet IPs, from the node subnet or from node pools' pod\_subnet\_id). - data\_plane: "cilium" (Azure CNI Powered by Cilium, recommended) or "azure". - policy: "cilium" (requires data\_plane = cilium), "calico", "azure" or "none". - pod\_cidr: overlay pod range (ignored in vnet mode). service\_cidr / dns\_service\_ip: Kubernetes   service range and kube-dns IP; they must not overlap the VNet, peered networks or pod\_cidr. - outbound\_type: loadBalancer, managedNATGateway, userAssignedNATGateway (NAT gateway attached to   the node subnet), userDefinedRouting (route table on the node subnet, e.g. via Azure Firewall) or none. - load\_balancer\_profile / nat\_gateway\_profile: optional egress tuning for loadBalancer / managedNATGateway. Changing most of these values recreates the cluster. | ```object({ cni_mode = optional(string, "overlay") data_plane = optional(string, "cilium") policy = optional(string, "cilium") pod_cidr = optional(string, "10.244.0.0/16") service_cidr = optional(string, "172.16.0.0/16") dns_service_ip = optional(string, "172.16.0.10") outbound_type = optional(string, "loadBalancer") load_balancer_profile = optional(object({ managed_outbound_ip_count = optional(number) outbound_ip_address_ids = optional(list(string)) outbound_ip_prefix_ids = optional(list(string)) idle_timeout_in_minutes = optional(number) outbound_ports_allocated = optional(number) })) nat_gateway_profile = optional(object({ managed_outbound_ip_count = optional(number) idle_timeout_in_minutes = optional(number) })) })``` | `{}` | no |
| network\_contributor\_subnet\_ids | Subnets (static key => subnet ID) on which the control plane identity is granted Network Contributor BEFORE the cluster is created (needed with bring-your-own VNet for load balancers, NAT/UDR egress). Keys must be static strings so the map works with subnets created in the same apply. Requires identity\_type = UserAssigned. | `map(string)` | `{}` | no |
| node\_os\_upgrade\_channel | Node OS image upgrade channel: NodeImage (recommended), SecurityPatch, Unmanaged or None. | `string` | `"NodeImage"` | no |
| node\_pools | Additional Linux node pools, keyed by pool name (1-12 lowercase letters/digits). Each pool inherits the system pool's vnet\_subnet\_id/pod\_subnet\_id unless set. - mode: User (workloads, default) or System. - auto\_scaling\_enabled with min\_count (User pools may scale to 0) / max\_count, or a fixed node\_count. - node\_labels / node\_taints ("key=value:NoSchedule\|PreferNoSchedule\|NoExecute"). - priority = "Spot" enables Spot VMs (eviction\_policy, spot\_max\_price = -1 for on-demand cap);   the AKS spot label and taint are added automatically. | ```map(object({ vm_size = string mode = optional(string, "User") os_sku = optional(string, "AzureLinux") vnet_subnet_id = optional(string) pod_subnet_id = optional(string) zones = optional(list(string), ["1", "2", "3"]) auto_scaling_enabled = optional(bool, true) node_count = optional(number, 1) min_count = optional(number, 1) max_count = optional(number, 3) max_pods = optional(number) os_disk_type = optional(string, "Managed") os_disk_size_gb = optional(number, 128) node_labels = optional(map(string), {}) node_taints = optional(list(string), []) priority = optional(string, "Regular") eviction_policy = optional(string, "Delete") spot_max_price = optional(number, -1) host_encryption_enabled = optional(bool, false) orchestrator_version = optional(string) upgrade_settings = optional(object({ max_surge = optional(string, "10%") drain_timeout_in_minutes = optional(number) node_soak_duration_in_minutes = optional(number) }), {}) tags = optional(map(string), {}) }))``` | `{}` | no |
| node\_resource\_group\_name | Name of the AKS-managed node resource group (must not exist yet). Defaults to the AKS naming (`MC_<rg>_<cluster>_<region>`). Forces a new cluster when changed. | `string` | `null` | no |
| oidc\_issuer\_enabled | Expose an OIDC issuer for the cluster (required by Workload Identity). Cannot be disabled once enabled. | `bool` | `true` | no |
| private\_cluster\_enabled | Expose the API server only on a private IP inside the cluster VNet. Operators and CI/CD then need private connectivity (VPN, peering, Bastion, self-hosted runners). Forces a new cluster when changed. | `bool` | `false` | no |
| private\_cluster\_public\_fqdn\_enabled | For private clusters, also publish a public FQDN (resolving to the private IP). Ignored for public clusters. | `bool` | `false` | no |
| private\_dns\_zone\_id | Private cluster DNS: "System" (AKS-managed zone), "None" (bring your own DNS resolution) or the resource ID of an existing `privatelink.<region>.azmk8s.io` zone. A custom zone requires a user-assigned identity that already holds Private DNS Zone Contributor on it (pass it via user\_assigned\_identity). Ignored for public clusters. | `string` | `"System"` | no |
| run\_command\_enabled | Allow `az aks command invoke` (runs kubectl through the Azure API). Useful for private clusters without network line of sight; disabled by default to reduce the attack surface. | `bool` | `false` | no |
| sku\_tier | AKS control plane tier: Free (no SLA, dev/test), Standard (financially backed SLA, recommended for production) or Premium (Standard + Long Term Support). | `string` | `"Standard"` | no |
| support\_plan | Support plan: KubernetesOfficial or AKSLongTermSupport (requires sku\_tier = Premium). | `string` | `"KubernetesOfficial"` | no |
| tags | Tags applied to every resource created by the module. | `map(string)` | `{}` | no |
| user\_assigned\_identity | Existing user-assigned identity for the control plane ({ id, principal\_id }). Null with identity\_type = UserAssigned makes the module create one named `id-<cluster name>`. Bring your own when it must hold permissions before the module runs (e.g. Private DNS Zone Contributor on a custom zone). | ```object({ id = string principal_id = string })``` | `null` | no |
| workload\_identity\_enabled | Enable Microsoft Entra Workload ID so pods authenticate to Azure (Key Vault, Storage, ...) with federated managed identities instead of secrets. | `bool` | `true` | no |

### Outputs

| Name | Description |
| ---- | ----------- |
| api\_server\_endpoint | HTTPS endpoint of the Kubernetes API server (private FQDN for private clusters). |
| cluster\_ca\_certificate | Base64-encoded cluster CA certificate, e.g. to configure the kubernetes/helm providers with exec-based (kubelogin) authentication. Marked sensitive because the provider exposes it inside the kube\_config block. |
| cluster\_identity | Control plane managed identity: type, principal (object) ID and, for user-assigned identities, the resource ID. |
| container\_insights\_data\_collection\_rule\_id | Resource ID of the Container Insights data collection rule (null when disabled). |
| current\_kubernetes\_version | Kubernetes version actually running (moves with auto-upgrades). |
| fqdn | Public FQDN of the API server (empty for private clusters without public FQDN). |
| get\_credentials\_command | Recommended way to obtain a kubeconfig: Entra ID based, nothing secret is written to Terraform state or outputs. With local accounts disabled, convert it for non-interactive use with `kubelogin convert-kubeconfig -l azurecli`. |
| id | Resource ID of the AKS cluster (scope for Azure RBAC role assignments). |
| key\_vault\_secrets\_provider\_identity | Identity of the Key Vault Secrets Store CSI driver add-on ({ client\_id, object\_id, user\_assigned\_identity\_id }), null when the add-on is disabled. Grant it Key Vault access when not using Workload Identity. |
| kube\_config\_raw | Raw kubeconfig of the (non-admin) cluster user. SENSITIVE: with local accounts enabled it embeds credentials. Prefer get\_credentials\_command. |
| kubelet\_identity | Kubelet managed identity ({ client\_id, object\_id, user\_assigned\_identity\_id }) used by nodes, e.g. to pull images. |
| kubernetes\_version | Kubernetes version requested for the control plane (as configured, or the AKS default selected at creation). |
| location | Azure region of the AKS cluster. |
| name | Name of the AKS cluster. |
| node\_pool\_ids | Map of additional node pool name => node pool resource ID. |
| node\_resource\_group | Name of the AKS-managed node resource group. |
| node\_resource\_group\_id | Resource ID of the AKS-managed node resource group. |
| oidc\_issuer\_url | OIDC issuer URL, used to federate Workload Identity credentials. |
| private\_fqdn | Private FQDN of the API server (private clusters only). |
| resource\_group\_name | Resource group of the AKS cluster. |
<!-- END_TF_DOCS -->
