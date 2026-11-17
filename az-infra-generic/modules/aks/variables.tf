# =============================================================================
# General
# =============================================================================

variable "name" {
  description = "Name of the AKS cluster (1-63 characters: letters, digits, hyphens, underscores; must start and end with a letter or digit)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9_-]{0,61}[a-zA-Z0-9])?$", var.name))
    error_message = "name must be 1-63 characters (letters, digits, '-', '_') and start/end with a letter or digit."
  }
}

variable "location" {
  description = "Azure region of the cluster (e.g. francecentral)."
  type        = string
}

variable "resource_group_name" {
  description = "Existing resource group in which the cluster and its module-managed resources are created."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix of the API server FQDN. Defaults to a sanitised version of the cluster name. Forces a new cluster when changed."
  type        = string
  default     = null

  validation {
    condition     = var.dns_prefix == null || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,52}[a-zA-Z0-9])?$", var.dns_prefix))
    error_message = "dns_prefix must be 1-54 characters (letters, digits, hyphens) and start/end with a letter or digit."
  }
}

variable "node_resource_group_name" {
  description = "Name of the AKS-managed node resource group (must not exist yet). Defaults to the AKS naming (MC_<rg>_<cluster>_<region>). Forces a new cluster when changed."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource created by the module."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Cluster version, tier and upgrades
# =============================================================================

variable "kubernetes_version" {
  description = "Kubernetes version of the control plane. Null = AKS default at creation. With automatic_upgrade_channel = \"patch\" use MAJOR.MINOR (e.g. \"1.33\"); with \"stable\"/\"rapid\" leave null, since AKS then moves the minor version itself."
  type        = string
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.kubernetes_version))
    error_message = "kubernetes_version must look like MAJOR.MINOR or MAJOR.MINOR.PATCH (e.g. 1.33 or 1.33.2)."
  }

  validation {
    condition = (
      var.kubernetes_version == null ? true :
      contains(["stable", "rapid"], coalesce(var.automatic_upgrade_channel, "none")) ? false :
      var.automatic_upgrade_channel == "patch" ? can(regex("^[0-9]+\\.[0-9]+$", var.kubernetes_version)) :
      true
    )
    error_message = "Avoid upgrade drift: with automatic_upgrade_channel = \"patch\" set kubernetes_version to MAJOR.MINOR (no patch); with \"stable\" or \"rapid\" leave kubernetes_version null."
  }
}

variable "sku_tier" {
  description = "AKS control plane tier: Free (no SLA, dev/test), Standard (financially backed SLA, recommended for production) or Premium (Standard + Long Term Support)."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "support_plan" {
  description = "Support plan: KubernetesOfficial or AKSLongTermSupport (requires sku_tier = Premium)."
  type        = string
  default     = "KubernetesOfficial"

  validation {
    condition     = contains(["KubernetesOfficial", "AKSLongTermSupport"], var.support_plan)
    error_message = "support_plan must be KubernetesOfficial or AKSLongTermSupport."
  }

  validation {
    condition     = var.support_plan != "AKSLongTermSupport" || var.sku_tier == "Premium"
    error_message = "support_plan = AKSLongTermSupport requires sku_tier = Premium."
  }
}

variable "automatic_upgrade_channel" {
  description = "Cluster auto-upgrade channel: patch (recommended), stable, rapid, node-image, or null for no automatic Kubernetes upgrades."
  type        = string
  default     = "patch"

  validation {
    condition     = contains(["patch", "stable", "rapid", "node-image", "none"], coalesce(var.automatic_upgrade_channel, "none"))
    error_message = "automatic_upgrade_channel must be patch, stable, rapid, node-image or null."
  }
}

variable "node_os_upgrade_channel" {
  description = "Node OS image upgrade channel: NodeImage (recommended), SecurityPatch, Unmanaged or None."
  type        = string
  default     = "NodeImage"

  validation {
    condition     = contains(["NodeImage", "SecurityPatch", "Unmanaged", "None"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be NodeImage, SecurityPatch, Unmanaged or None."
  }

  validation {
    condition     = coalesce(var.automatic_upgrade_channel, "none") != "node-image" || var.node_os_upgrade_channel == "NodeImage"
    error_message = "node_os_upgrade_channel must be NodeImage when automatic_upgrade_channel = \"node-image\"."
  }
}

variable "maintenance_windows" {
  description = <<-EOT
    Planned maintenance windows. `auto_upgrade` constrains cluster auto-upgrades,
    `node_os` constrains node OS image updates. A null window means "any time".
    Each window: frequency (Daily | Weekly | AbsoluteMonthly | RelativeMonthly),
    interval, duration in hours (4-24), day_of_week (Weekly, RelativeMonthly),
    day_of_month (AbsoluteMonthly), week_index (RelativeMonthly: First..Last),
    start_time ("HH:mm"), utc_offset ("+01:00"), not_allowed periods (RFC3339).
  EOT
  type = object({
    auto_upgrade = optional(object({
      frequency    = string
      interval     = optional(number, 1)
      duration     = optional(number, 4)
      day_of_week  = optional(string)
      day_of_month = optional(number)
      week_index   = optional(string)
      start_time   = optional(string)
      utc_offset   = optional(string)
      not_allowed  = optional(list(object({ start = string, end = string })), [])
    }))
    node_os = optional(object({
      frequency    = string
      interval     = optional(number, 1)
      duration     = optional(number, 4)
      day_of_week  = optional(string)
      day_of_month = optional(number)
      week_index   = optional(string)
      start_time   = optional(string)
      utc_offset   = optional(string)
      not_allowed  = optional(list(object({ start = string, end = string })), [])
    }))
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for w in [var.maintenance_windows.auto_upgrade, var.maintenance_windows.node_os] :
      contains(["Daily", "Weekly", "AbsoluteMonthly", "RelativeMonthly"], w.frequency) && w.duration >= 4 && w.duration <= 24 && w.interval >= 1
      if w != null
    ])
    error_message = "Maintenance window frequency must be Daily, Weekly, AbsoluteMonthly or RelativeMonthly; duration 4-24 hours; interval >= 1."
  }

  validation {
    condition = alltrue([
      for w in [var.maintenance_windows.auto_upgrade, var.maintenance_windows.node_os] : (
        w.frequency == "Weekly" ? w.day_of_week != null :
        w.frequency == "AbsoluteMonthly" ? w.day_of_month != null :
        w.frequency == "RelativeMonthly" ? (w.day_of_week != null && w.week_index != null) :
        true
      )
      if w != null
    ])
    error_message = "Weekly windows need day_of_week, AbsoluteMonthly needs day_of_month, RelativeMonthly needs day_of_week and week_index."
  }

  validation {
    condition = alltrue([
      for w in [var.maintenance_windows.auto_upgrade, var.maintenance_windows.node_os] :
      w.start_time == null ? true : can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", w.start_time))
      if w != null
    ])
    error_message = "Maintenance window start_time must use the HH:mm format."
  }
}

# =============================================================================
# Identity
# =============================================================================

variable "identity_type" {
  description = "Control plane managed identity: UserAssigned (recommended: its principal exists before the cluster, so network/DNS permissions can be granted first) or SystemAssigned."
  type        = string
  default     = "UserAssigned"

  validation {
    condition     = contains(["UserAssigned", "SystemAssigned"], var.identity_type)
    error_message = "identity_type must be UserAssigned or SystemAssigned."
  }
}

variable "user_assigned_identity" {
  description = "Existing user-assigned identity for the control plane ({ id, principal_id }). Null with identity_type = UserAssigned makes the module create one named id-<cluster name>. Bring your own when it must hold permissions before the module runs (e.g. Private DNS Zone Contributor on a custom zone)."
  type = object({
    id           = string
    principal_id = string
  })
  default = null

  validation {
    condition     = var.user_assigned_identity == null || var.identity_type == "UserAssigned"
    error_message = "user_assigned_identity can only be set when identity_type = \"UserAssigned\"."
  }

  validation {
    condition     = var.user_assigned_identity == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.ManagedIdentity/userAssignedIdentities/[^/]+$", var.user_assigned_identity.id))
    error_message = "user_assigned_identity.id must be the resource ID of a user-assigned managed identity."
  }
}

# =============================================================================
# Access control
# =============================================================================

variable "entra_id_rbac" {
  description = "AKS-managed Microsoft Entra ID integration. azure_rbac_enabled = true authorises Kubernetes access with Azure role assignments; admin_group_object_ids get cluster-admin. tenant_id defaults to the provider's tenant. Null disables the integration (only possible with local accounts enabled)."
  type = object({
    azure_rbac_enabled     = optional(bool, true)
    admin_group_object_ids = optional(list(string), [])
    tenant_id              = optional(string)
  })
  default = {}

  validation {
    condition = var.entra_id_rbac == null ? true : alltrue([
      for id in var.entra_id_rbac.admin_group_object_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "entra_id_rbac.admin_group_object_ids must contain Entra ID group object IDs (GUIDs)."
  }
}

variable "cluster_admin_principal_ids" {
  description = "Entra ID principals (static key => object ID of a user, group or service principal) granted \"Azure Kubernetes Service RBAC Cluster Admin\" on the cluster. Requires entra_id_rbac.azure_rbac_enabled. Prefer groups; for a first deployment, the deploying principal avoids being locked out."
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.cluster_admin_principal_ids) == 0 || try(var.entra_id_rbac.azure_rbac_enabled, false)
    error_message = "cluster_admin_principal_ids requires entra_id_rbac.azure_rbac_enabled = true."
  }
}

variable "local_account_disabled" {
  description = "Disable the static local admin kubeconfig so every access goes through Microsoft Entra ID (recommended). Requires entra_id_rbac."
  type        = bool
  default     = true

  validation {
    condition     = !var.local_account_disabled || var.entra_id_rbac != null
    error_message = "local_account_disabled = true requires entra_id_rbac (Entra ID integration) to be enabled."
  }
}

variable "run_command_enabled" {
  description = "Allow `az aks command invoke` (runs kubectl through the Azure API). Useful for private clusters without network line of sight; disabled by default to reduce the attack surface."
  type        = bool
  default     = false
}

# =============================================================================
# Networking
# =============================================================================

variable "network" {
  description = <<-EOT
    Azure CNI configuration (the network plugin is always `azure`).
    - cni_mode: "overlay" (recommended; pods get IPs from pod_cidr, VNet IPs are only used by nodes)
      or "vnet" (pods get VNet IPs, from the node subnet or from node pools' pod_subnet_id).
    - data_plane: "cilium" (Azure CNI Powered by Cilium, recommended) or "azure".
    - policy: "cilium" (requires data_plane = cilium), "calico", "azure" or "none".
    - pod_cidr: overlay pod range (ignored in vnet mode). service_cidr / dns_service_ip: Kubernetes
      service range and kube-dns IP; they must not overlap the VNet, peered networks or pod_cidr.
    - outbound_type: loadBalancer, managedNATGateway, userAssignedNATGateway (NAT gateway attached to
      the node subnet), userDefinedRouting (route table on the node subnet, e.g. via Azure Firewall) or none.
    - load_balancer_profile / nat_gateway_profile: optional egress tuning for loadBalancer / managedNATGateway.
    Changing most of these values recreates the cluster.
  EOT
  type = object({
    cni_mode       = optional(string, "overlay")
    data_plane     = optional(string, "cilium")
    policy         = optional(string, "cilium")
    pod_cidr       = optional(string, "10.244.0.0/16")
    service_cidr   = optional(string, "172.16.0.0/16")
    dns_service_ip = optional(string, "172.16.0.10")
    outbound_type  = optional(string, "loadBalancer")
    load_balancer_profile = optional(object({
      managed_outbound_ip_count = optional(number)
      outbound_ip_address_ids   = optional(list(string))
      outbound_ip_prefix_ids    = optional(list(string))
      idle_timeout_in_minutes   = optional(number)
      outbound_ports_allocated  = optional(number)
    }))
    nat_gateway_profile = optional(object({
      managed_outbound_ip_count = optional(number)
      idle_timeout_in_minutes   = optional(number)
    }))
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["overlay", "vnet"], var.network.cni_mode)
    error_message = "network.cni_mode must be \"overlay\" or \"vnet\"."
  }

  validation {
    condition     = contains(["cilium", "azure"], var.network.data_plane) && contains(["cilium", "calico", "azure", "none"], var.network.policy)
    error_message = "network.data_plane must be cilium or azure; network.policy must be cilium, calico, azure or none."
  }

  validation {
    condition     = (var.network.data_plane == "cilium") == (var.network.policy == "cilium")
    error_message = "The cilium data plane always enforces cilium network policies: use data_plane = \"cilium\" with policy = \"cilium\" (or another policy with data_plane = \"azure\")."
  }

  validation {
    condition     = can(cidrhost(var.network.service_cidr, 0)) && can(cidrhost(var.network.pod_cidr, 0)) && can(cidrhost("${var.network.dns_service_ip}/32", 0))
    error_message = "network.service_cidr and network.pod_cidr must be valid CIDR ranges and network.dns_service_ip a valid IPv4 address."
  }

  validation {
    # dns_service_ip must belong to service_cidr and must not be its network
    # address nor its first host (reserved for the kubernetes API service).
    condition = try(
      cidrhost("${var.network.dns_service_ip}/${split("/", var.network.service_cidr)[1]}", 0) == cidrhost(var.network.service_cidr, 0) &&
      var.network.dns_service_ip != cidrhost(var.network.service_cidr, 0) &&
      var.network.dns_service_ip != cidrhost(var.network.service_cidr, 1),
      false,
    )
    error_message = "network.dns_service_ip must be inside network.service_cidr and must not be its first two addresses (e.g. 172.16.0.10 for 172.16.0.0/16)."
  }

  validation {
    # Two ranges overlap when their network addresses match at the shorter prefix.
    # Malformed ranges are reported by the format validation above.
    condition = var.network.cni_mode != "overlay" ? true : try(
      cidrhost("${split("/", var.network.pod_cidr)[0]}/${min(tonumber(split("/", var.network.pod_cidr)[1]), tonumber(split("/", var.network.service_cidr)[1]))}", 0) !=
      cidrhost("${split("/", var.network.service_cidr)[0]}/${min(tonumber(split("/", var.network.pod_cidr)[1]), tonumber(split("/", var.network.service_cidr)[1]))}", 0),
      true,
    )
    error_message = "network.pod_cidr and network.service_cidr must not overlap."
  }

  validation {
    condition     = contains(["loadBalancer", "managedNATGateway", "userAssignedNATGateway", "userDefinedRouting", "none"], var.network.outbound_type)
    error_message = "network.outbound_type must be loadBalancer, managedNATGateway, userAssignedNATGateway, userDefinedRouting or none."
  }

  validation {
    condition     = var.network.load_balancer_profile == null || var.network.outbound_type == "loadBalancer"
    error_message = "network.load_balancer_profile can only be set with outbound_type = \"loadBalancer\"."
  }

  validation {
    condition     = var.network.nat_gateway_profile == null || var.network.outbound_type == "managedNATGateway"
    error_message = "network.nat_gateway_profile can only be set with outbound_type = \"managedNATGateway\"."
  }

  validation {
    condition = var.network.load_balancer_profile == null ? true : length([
      for v in [
        var.network.load_balancer_profile.managed_outbound_ip_count,
        var.network.load_balancer_profile.outbound_ip_address_ids,
        var.network.load_balancer_profile.outbound_ip_prefix_ids,
      ] : v if v != null
    ]) <= 1
    error_message = "network.load_balancer_profile: managed_outbound_ip_count, outbound_ip_address_ids and outbound_ip_prefix_ids are mutually exclusive."
  }
}

variable "private_cluster_enabled" {
  description = "Expose the API server only on a private IP inside the cluster VNet. Operators and CI/CD then need private connectivity (VPN, peering, Bastion, self-hosted runners). Forces a new cluster when changed."
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "Private cluster DNS: \"System\" (AKS-managed zone), \"None\" (bring your own DNS resolution) or the resource ID of an existing privatelink.<region>.azmk8s.io zone. A custom zone requires a user-assigned identity that already holds Private DNS Zone Contributor on it (pass it via user_assigned_identity). Ignored for public clusters."
  type        = string
  default     = "System"

  validation {
    condition     = contains(["System", "None"], var.private_dns_zone_id) || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/privateDnsZones/[^/]+$", var.private_dns_zone_id))
    error_message = "private_dns_zone_id must be \"System\", \"None\" or a private DNS zone resource ID."
  }

  validation {
    condition     = contains(["System", "None"], var.private_dns_zone_id) || var.identity_type == "UserAssigned"
    error_message = "A custom private DNS zone requires identity_type = \"UserAssigned\"."
  }
}

variable "private_cluster_public_fqdn_enabled" {
  description = "For private clusters, also publish a public FQDN (resolving to the private IP). Ignored for public clusters."
  type        = bool
  default     = false
}

variable "api_server_authorized_ip_ranges" {
  description = "Public CIDR ranges allowed to reach a PUBLIC API server (e.g. office egress, CI runners). Empty = reachable from anywhere (still authenticated). Not supported with private_cluster_enabled."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for r in var.api_server_authorized_ip_ranges : can(cidrhost(r, 0))])
    error_message = "api_server_authorized_ip_ranges must contain CIDR ranges (use /32 for a single address)."
  }

  validation {
    condition     = !var.private_cluster_enabled || length(var.api_server_authorized_ip_ranges) == 0
    error_message = "api_server_authorized_ip_ranges cannot be used with a private cluster."
  }
}

variable "network_contributor_subnet_ids" {
  description = "Subnets (static key => subnet ID) on which the control plane identity is granted Network Contributor BEFORE the cluster is created (needed with bring-your-own VNet for load balancers, NAT/UDR egress). Keys must be static strings so the map works with subnets created in the same apply. Requires identity_type = UserAssigned."
  type        = map(string)
  default     = {}

  validation {
    condition     = length(var.network_contributor_subnet_ids) == 0 || var.identity_type == "UserAssigned"
    error_message = "network_contributor_subnet_ids requires identity_type = \"UserAssigned\" (a system-assigned principal does not exist before the cluster)."
  }
}

# =============================================================================
# Default (system) node pool
# =============================================================================

variable "default_node_pool" {
  description = <<-EOT
    System node pool (Linux). Main settings:
    - vnet_subnet_id: node subnet (null = AKS-managed VNet); pod_subnet_id: dedicated pod subnet (vnet CNI mode only).
    - zones: availability zones (set [] in regions without zones).
    - auto_scaling_enabled with min_count/max_count, or a fixed node_count. With autoscaling the pool
      starts at min_count and Terraform never fights the cluster autoscaler.
    - only_critical_addons_enabled: taint the pool CriticalAddonsOnly=true:NoSchedule so it only runs
      system pods (recommended; then declare at least one User pool in node_pools).
    - os_disk_type: Managed or Ephemeral (Ephemeral needs a VM size whose cache/temp disk fits os_disk_size_gb).
    - host_encryption_enabled: encryption at host (requires the EncryptionAtHost subscription feature).
    - temporary_name_for_rotation: name used to rotate the pool when an immutable setting changes
      (defaults to a generated name), so vm_size/zones/disk changes do not recreate the cluster.
  EOT
  type = object({
    name                         = optional(string, "system")
    vm_size                      = optional(string, "Standard_D4ds_v5")
    vnet_subnet_id               = optional(string)
    pod_subnet_id                = optional(string)
    zones                        = optional(list(string), ["1", "2", "3"])
    auto_scaling_enabled         = optional(bool, true)
    node_count                   = optional(number, 3)
    min_count                    = optional(number, 3)
    max_count                    = optional(number, 5)
    max_pods                     = optional(number)
    os_sku                       = optional(string, "AzureLinux")
    os_disk_type                 = optional(string, "Managed")
    os_disk_size_gb              = optional(number, 128)
    only_critical_addons_enabled = optional(bool, true)
    host_encryption_enabled      = optional(bool, false)
    orchestrator_version         = optional(string)
    node_labels                  = optional(map(string), {})
    temporary_name_for_rotation  = optional(string)
    upgrade_settings = optional(object({
      max_surge                     = optional(string, "10%")
      drain_timeout_in_minutes      = optional(number)
      node_soak_duration_in_minutes = optional(number)
    }), {})
    tags = optional(map(string), {})
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,11}$", var.default_node_pool.name))
    error_message = "default_node_pool.name must be 1-12 lowercase letters/digits starting with a letter."
  }

  validation {
    condition = var.default_node_pool.temporary_name_for_rotation == null ? true : (
      can(regex("^[a-z][a-z0-9]{0,11}$", var.default_node_pool.temporary_name_for_rotation)) &&
      var.default_node_pool.temporary_name_for_rotation != var.default_node_pool.name
    )
    error_message = "default_node_pool.temporary_name_for_rotation must be 1-12 lowercase letters/digits starting with a letter, different from the pool name."
  }

  validation {
    condition = (
      var.default_node_pool.auto_scaling_enabled ?
      var.default_node_pool.min_count >= 1 && var.default_node_pool.min_count <= var.default_node_pool.max_count && var.default_node_pool.max_count <= 1000 :
      var.default_node_pool.node_count >= 1 && var.default_node_pool.node_count <= 1000
    )
    error_message = "System pool sizing: with autoscaling 1 <= min_count <= max_count <= 1000, otherwise 1 <= node_count <= 1000."
  }

  validation {
    condition     = alltrue([for z in var.default_node_pool.zones : contains(["1", "2", "3"], z)])
    error_message = "default_node_pool.zones must be a subset of [\"1\", \"2\", \"3\"]."
  }

  validation {
    condition = (
      contains(["Managed", "Ephemeral"], var.default_node_pool.os_disk_type) &&
      contains(["AzureLinux", "AzureLinux3", "Ubuntu", "Ubuntu2204", "Ubuntu2404"], var.default_node_pool.os_sku) &&
      var.default_node_pool.os_disk_size_gb >= 30 && var.default_node_pool.os_disk_size_gb <= 2048
    )
    error_message = "default_node_pool: os_disk_type must be Managed or Ephemeral, os_sku a Linux SKU (AzureLinux, AzureLinux3, Ubuntu, Ubuntu2204, Ubuntu2404), os_disk_size_gb between 30 and 2048."
  }

  validation {
    condition     = can(regex("^[0-9]+%?$", var.default_node_pool.upgrade_settings.max_surge))
    error_message = "default_node_pool.upgrade_settings.max_surge must be a node count (e.g. \"1\") or a percentage (e.g. \"33%\")."
  }

  validation {
    condition = (
      var.default_node_pool.orchestrator_version == null ? true :
      contains(["stable", "rapid"], coalesce(var.automatic_upgrade_channel, "none")) ? false :
      var.automatic_upgrade_channel == "patch" ? can(regex("^[0-9]+\\.[0-9]+$", var.default_node_pool.orchestrator_version)) :
      can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.default_node_pool.orchestrator_version))
    )
    error_message = "default_node_pool.orchestrator_version follows the kubernetes_version rules: MAJOR.MINOR with the patch channel, null with stable/rapid."
  }

  validation {
    condition     = var.default_node_pool.pod_subnet_id == null || var.network.cni_mode == "vnet"
    error_message = "default_node_pool.pod_subnet_id is only supported with network.cni_mode = \"vnet\"."
  }

  validation {
    condition     = !(var.network.cni_mode == "vnet" && var.network.data_plane == "cilium") || var.default_node_pool.pod_subnet_id != null
    error_message = "The cilium data plane in vnet CNI mode requires a dedicated pod subnet (default_node_pool.pod_subnet_id)."
  }

  validation {
    condition     = !contains(["userDefinedRouting", "userAssignedNATGateway"], var.network.outbound_type) || var.default_node_pool.vnet_subnet_id != null
    error_message = "outbound_type userDefinedRouting / userAssignedNATGateway requires a bring-your-own node subnet (default_node_pool.vnet_subnet_id)."
  }
}

# =============================================================================
# Additional node pools
# =============================================================================

variable "node_pools" {
  description = <<-EOT
    Additional Linux node pools, keyed by pool name (1-12 lowercase letters/digits).
    Each pool inherits the system pool's vnet_subnet_id/pod_subnet_id unless set.
    - mode: User (workloads, default) or System.
    - auto_scaling_enabled with min_count (User pools may scale to 0) / max_count, or a fixed node_count.
    - node_labels / node_taints ("key=value:NoSchedule|PreferNoSchedule|NoExecute").
    - priority = "Spot" enables Spot VMs (eviction_policy, spot_max_price = -1 for on-demand cap);
      the AKS spot label and taint are added automatically.
  EOT
  type = map(object({
    vm_size                 = string
    mode                    = optional(string, "User")
    os_sku                  = optional(string, "AzureLinux")
    vnet_subnet_id          = optional(string)
    pod_subnet_id           = optional(string)
    zones                   = optional(list(string), ["1", "2", "3"])
    auto_scaling_enabled    = optional(bool, true)
    node_count              = optional(number, 1)
    min_count               = optional(number, 1)
    max_count               = optional(number, 3)
    max_pods                = optional(number)
    os_disk_type            = optional(string, "Managed")
    os_disk_size_gb         = optional(number, 128)
    node_labels             = optional(map(string), {})
    node_taints             = optional(list(string), [])
    priority                = optional(string, "Regular")
    eviction_policy         = optional(string, "Delete")
    spot_max_price          = optional(number, -1)
    host_encryption_enabled = optional(bool, false)
    orchestrator_version    = optional(string)
    upgrade_settings = optional(object({
      max_surge                     = optional(string, "10%")
      drain_timeout_in_minutes      = optional(number)
      node_soak_duration_in_minutes = optional(number)
    }), {})
    tags = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for name, pool in var.node_pools :
      can(regex("^[a-z][a-z0-9]{0,11}$", name)) && name != var.default_node_pool.name
    ])
    error_message = "node_pools keys must be 1-12 lowercase letters/digits starting with a letter and differ from default_node_pool.name."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) :
      contains(["User", "System"], pool.mode) && contains(["Regular", "Spot"], pool.priority) &&
      contains(["Managed", "Ephemeral"], pool.os_disk_type) &&
      contains(["AzureLinux", "AzureLinux3", "Ubuntu", "Ubuntu2204", "Ubuntu2404"], pool.os_sku)
    ])
    error_message = "node_pools: mode must be User or System, priority Regular or Spot, os_disk_type Managed or Ephemeral, os_sku a Linux SKU."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) : (
        pool.auto_scaling_enabled ?
        pool.min_count >= (pool.mode == "System" ? 1 : 0) && pool.min_count <= pool.max_count && pool.max_count <= 1000 && pool.max_count >= 1 :
        pool.node_count >= (pool.mode == "System" ? 1 : 0) && pool.node_count <= 1000
      )
    ])
    error_message = "node_pools sizing: with autoscaling min_count <= max_count <= 1000 (min_count >= 1 for System pools, >= 0 for User pools); otherwise node_count between 0 (User) / 1 (System) and 1000."
  }

  validation {
    condition     = alltrue([for pool in values(var.node_pools) : alltrue([for z in pool.zones : contains(["1", "2", "3"], z)])])
    error_message = "node_pools zones must be subsets of [\"1\", \"2\", \"3\"]."
  }

  validation {
    condition = alltrue(flatten([
      for pool in values(var.node_pools) : [
        for taint in pool.node_taints : can(regex("^[A-Za-z0-9./_-]+(=[A-Za-z0-9._-]*)?:(NoSchedule|PreferNoSchedule|NoExecute)$", taint))
      ]
    ]))
    error_message = "node_pools taints must look like key=value:NoSchedule (effects: NoSchedule, PreferNoSchedule, NoExecute)."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) :
      pool.priority == "Regular" ? true : (pool.mode == "User" && contains(["Delete", "Deallocate"], pool.eviction_policy) && (pool.spot_max_price == -1 || pool.spot_max_price > 0))
    ])
    error_message = "Spot node pools must be User pools with eviction_policy Delete or Deallocate and spot_max_price -1 or > 0."
  }

  validation {
    condition     = alltrue([for pool in values(var.node_pools) : pool.pod_subnet_id == null || var.network.cni_mode == "vnet"])
    error_message = "node_pools pod_subnet_id is only supported with network.cni_mode = \"vnet\"."
  }

  validation {
    condition     = alltrue([for pool in values(var.node_pools) : var.default_node_pool.vnet_subnet_id != null || pool.vnet_subnet_id == null])
    error_message = "node_pools cannot use their own vnet_subnet_id when the system pool uses the AKS-managed VNet (all pools must share one VNet)."
  }

  validation {
    condition     = alltrue([for pool in values(var.node_pools) : can(regex("^[0-9]+%?$", pool.upgrade_settings.max_surge))])
    error_message = "node_pools upgrade_settings.max_surge must be a node count (e.g. \"1\") or a percentage (e.g. \"33%\")."
  }

  validation {
    condition = alltrue([
      for pool in values(var.node_pools) : (
        pool.orchestrator_version == null ? true :
        contains(["stable", "rapid"], coalesce(var.automatic_upgrade_channel, "none")) ? false :
        var.automatic_upgrade_channel == "patch" ? can(regex("^[0-9]+\\.[0-9]+$", pool.orchestrator_version)) :
        can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", pool.orchestrator_version))
      )
    ])
    error_message = "node_pools orchestrator_version follows the kubernetes_version rules: MAJOR.MINOR with the patch channel, null with stable/rapid."
  }
}

variable "auto_scaler_profile" {
  description = "Optional cluster autoscaler tuning shared by all autoscaled pools. Null keeps the AKS defaults. Durations use Go syntax (e.g. \"10m\")."
  type = object({
    balance_similar_node_groups      = optional(bool)
    expander                         = optional(string)
    max_graceful_termination_sec     = optional(number)
    max_node_provisioning_time       = optional(string)
    scan_interval                    = optional(string)
    scale_down_delay_after_add       = optional(string)
    scale_down_unneeded              = optional(string)
    scale_down_utilization_threshold = optional(number)
    skip_nodes_with_local_storage    = optional(bool)
    skip_nodes_with_system_pods      = optional(bool)
  })
  default = null

  validation {
    condition     = var.auto_scaler_profile == null ? true : contains(["least-waste", "priority", "most-pods", "random", "none"], coalesce(var.auto_scaler_profile.expander, "none"))
    error_message = "auto_scaler_profile.expander must be least-waste, priority, most-pods or random."
  }
}

# =============================================================================
# Security
# =============================================================================

variable "oidc_issuer_enabled" {
  description = "Expose an OIDC issuer for the cluster (required by Workload Identity). Cannot be disabled once enabled."
  type        = bool
  default     = true
}

variable "workload_identity_enabled" {
  description = "Enable Microsoft Entra Workload ID so pods authenticate to Azure (Key Vault, Storage, ...) with federated managed identities instead of secrets."
  type        = bool
  default     = true

  validation {
    condition     = !var.workload_identity_enabled || var.oidc_issuer_enabled
    error_message = "workload_identity_enabled requires oidc_issuer_enabled = true."
  }
}

variable "azure_policy_enabled" {
  description = "Install the Azure Policy add-on (Gatekeeper) to audit/enforce policy assignments on the cluster. Requires the Microsoft.PolicyInsights resource provider."
  type        = bool
  default     = true
}

variable "key_vault_secrets_provider" {
  description = "Azure Key Vault Secrets Store CSI driver add-on: mounts Key Vault secrets/certificates into pods (authorise it with Workload Identity or the add-on identity exposed in outputs)."
  type = object({
    enabled                  = optional(bool, true)
    secret_rotation_enabled  = optional(bool, true)
    secret_rotation_interval = optional(string, "2m")
  })
  default  = {}
  nullable = false

  validation {
    condition     = can(regex("^[0-9]+(s|m|h)$", var.key_vault_secrets_provider.secret_rotation_interval))
    error_message = "key_vault_secrets_provider.secret_rotation_interval must be a duration such as 2m, 30s or 1h."
  }
}

variable "key_management_service" {
  description = "Optional KMS etcd encryption of Kubernetes secrets with a Key Vault key. Requires identity_type = UserAssigned and, BEFORE the cluster is created, the control plane identity must hold \"Key Vault Crypto User\" on the key (bring the identity through user_assigned_identity). key_vault_id is required for a versionless key (automatic rotation) or a private vault."
  type = object({
    key_vault_key_id         = string
    key_vault_network_access = optional(string, "Public")
    key_vault_id             = optional(string)
  })
  default = null

  validation {
    condition     = var.key_management_service == null || var.identity_type == "UserAssigned"
    error_message = "key_management_service requires identity_type = \"UserAssigned\"."
  }

  validation {
    condition = var.key_management_service == null ? true : (
      can(regex("^https://[^/]+/keys/[^/]+(/[^/]+)?$", var.key_management_service.key_vault_key_id)) &&
      contains(["Public", "Private"], var.key_management_service.key_vault_network_access)
    )
    error_message = "key_management_service.key_vault_key_id must be a Key Vault key URI (https://<vault>.vault.azure.net/keys/<name>[/<version>]) and key_vault_network_access Public or Private."
  }

  validation {
    condition = var.key_management_service == null ? true : (
      var.key_management_service.key_vault_id != null || (
        var.key_management_service.key_vault_network_access == "Public" &&
        can(regex("^https://[^/]+/keys/[^/]+/[^/]+$", var.key_management_service.key_vault_key_id))
      )
    )
    error_message = "key_management_service.key_vault_id is required with a versionless key ID or key_vault_network_access = \"Private\"."
  }
}

variable "disk_encryption_set_id" {
  description = "Optional Disk Encryption Set (customer-managed keys) for node OS and data disks. Forces a new cluster when changed."
  type        = string
  default     = null

  validation {
    condition     = var.disk_encryption_set_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Compute/diskEncryptionSets/[^/]+$", var.disk_encryption_set_id))
    error_message = "disk_encryption_set_id must be the resource ID of a disk encryption set."
  }
}

variable "image_cleaner_enabled" {
  description = "Run Image Cleaner (Eraser) to remove unused, potentially vulnerable images from nodes."
  type        = bool
  default     = true
}

variable "image_cleaner_interval_hours" {
  description = "Image Cleaner scan interval in hours (24-2160)."
  type        = number
  default     = 168

  validation {
    condition     = var.image_cleaner_interval_hours >= 24 && var.image_cleaner_interval_hours <= 2160
    error_message = "image_cleaner_interval_hours must be between 24 and 2160."
  }
}

variable "microsoft_defender_enabled" {
  description = "Enable the Microsoft Defender for Containers sensor (runtime threat detection; billed by Defender for Cloud). Sends its data to monitoring.log_analytics_workspace_id."
  type        = bool
  default     = false

  validation {
    condition     = !var.microsoft_defender_enabled || var.monitoring != null
    error_message = "microsoft_defender_enabled requires monitoring.log_analytics_workspace_id."
  }
}

variable "container_registry_ids" {
  description = "Azure Container Registries (static key => registry ID) the kubelet identity may pull from (AcrPull role). Keys must be static strings so registries created in the same apply are supported."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Observability
# =============================================================================

variable "monitoring" {
  description = <<-EOT
    Azure Monitor integration. Null disables it. log_analytics_workspace_id is required.
    - container_insights_enabled: Container Insights agent with managed identity authentication,
      wired through a data collection rule (DCR) and its association to the cluster.
    - container_insights_streams / data_collection_interval / namespace_filtering_mode (Off | Include | Exclude)
      / namespaces: Container Insights collection scope (cost control).
    - data_collection_rule_location: region of the Container Insights data collection rule; it must be the
      region of the Log Analytics workspace (defaults to the cluster region).
    - diagnostic_settings_enabled: control plane logs (resource-specific tables) and metrics to the workspace;
      diagnostic_log_categories selects the log categories (kube-audit is very verbose: prefer kube-audit-admin).
  EOT
  type = object({
    log_analytics_workspace_id = string
    container_insights_enabled = optional(bool, true)
    container_insights_streams = optional(list(string), [
      "Microsoft-ContainerLog",
      "Microsoft-ContainerLogV2",
      "Microsoft-KubeEvents",
      "Microsoft-KubePodInventory",
      "Microsoft-KubeNodeInventory",
      "Microsoft-KubePVInventory",
      "Microsoft-KubeServices",
      "Microsoft-KubeMonAgentEvents",
      "Microsoft-InsightsMetrics",
      "Microsoft-ContainerInventory",
      "Microsoft-ContainerNodeInventory",
      "Microsoft-Perf",
    ])
    data_collection_rule_location = optional(string)
    data_collection_interval      = optional(string, "1m")
    namespace_filtering_mode      = optional(string, "Off")
    namespaces                    = optional(list(string), [])
    diagnostic_settings_enabled   = optional(bool, true)
    diagnostic_log_categories = optional(list(string), [
      "kube-apiserver",
      "kube-audit-admin",
      "kube-controller-manager",
      "kube-scheduler",
      "cluster-autoscaler",
      "guard",
    ])
    diagnostic_metrics_enabled = optional(bool, true)
  })
  default = null

  validation {
    condition     = var.monitoring == null ? true : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+$", var.monitoring.log_analytics_workspace_id))
    error_message = "monitoring.log_analytics_workspace_id must be the resource ID of a Log Analytics workspace."
  }

  validation {
    condition     = var.monitoring == null ? true : can(regex("^([1-9]|[12][0-9]|30)m$", var.monitoring.data_collection_interval))
    error_message = "monitoring.data_collection_interval must be between 1m and 30m."
  }

  validation {
    condition = var.monitoring == null ? true : (
      contains(["Off", "Include", "Exclude"], var.monitoring.namespace_filtering_mode) &&
      (var.monitoring.namespace_filtering_mode == "Off" || length(var.monitoring.namespaces) > 0)
    )
    error_message = "monitoring.namespace_filtering_mode must be Off, Include or Exclude; Include/Exclude need a non-empty namespaces list."
  }

  validation {
    condition = var.monitoring == null ? true : alltrue([
      for c in var.monitoring.diagnostic_log_categories : contains([
        "kube-apiserver", "kube-audit", "kube-audit-admin", "kube-controller-manager", "kube-scheduler",
        "cluster-autoscaler", "cloud-controller-manager", "guard", "csi-azuredisk-controller",
        "csi-azurefile-controller", "csi-snapshot-controller",
      ], c)
    ])
    error_message = "monitoring.diagnostic_log_categories contains an unknown AKS log category."
  }

  validation {
    condition     = var.monitoring == null ? true : !var.monitoring.container_insights_enabled || length(var.monitoring.container_insights_streams) > 0
    error_message = "monitoring.container_insights_streams cannot be empty when Container Insights is enabled."
  }
}
