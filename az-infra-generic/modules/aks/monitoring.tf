# =============================================================================
# Azure Monitor integration (Log Analytics)
#
# Container Insights with managed identity authentication needs a data
# collection rule (DCR) associated to the cluster: unlike the Azure CLI, the
# AKS API does not create it, so without these two resources the agent runs
# but no data reaches the workspace.
# =============================================================================

resource "azurerm_monitor_data_collection_rule" "container_insights" {
  count = local.container_insights_enabled ? 1 : 0

  # "MSCI-<region>-<cluster>" is the naming used by the Azure CLI and portal.
  # The rule lives in the region of its destination workspace.
  name                = substr("MSCI-${local.data_collection_rule_location}-${var.name}", 0, 64)
  resource_group_name = var.resource_group_name
  location            = local.data_collection_rule_location
  description         = "Container Insights data collection for AKS cluster ${var.name}."
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "ciworkspace"
      workspace_resource_id = var.monitoring.log_analytics_workspace_id
    }
  }

  data_flow {
    streams      = var.monitoring.container_insights_streams
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = var.monitoring.container_insights_streams
      extension_json = jsonencode({
        dataCollectionSettings = merge(
          {
            interval               = var.monitoring.data_collection_interval
            namespaceFilteringMode = var.monitoring.namespace_filtering_mode
            enableContainerLogV2   = true
          },
          var.monitoring.namespace_filtering_mode == "Off" ? {} : { namespaces = var.monitoring.namespaces },
        )
      })
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  count = local.container_insights_enabled ? 1 : 0

  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights[0].id
  description             = "Container Insights collection for this cluster. Deleting this association stops data collection."
}

# Control plane logs and platform metrics. "Dedicated" sends logs to the
# resource-specific tables (AKSAudit, AKSAuditAdmin, AKSControlPlane), which
# are cheaper to query than the legacy AzureDiagnostics table.
resource "azurerm_monitor_diagnostic_setting" "cluster" {
  count = local.diagnostic_settings_enabled ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id     = var.monitoring.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = toset(var.monitoring.diagnostic_log_categories)

    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_metric" {
    for_each = var.monitoring.diagnostic_metrics_enabled ? ["AllMetrics"] : []

    content {
      category = enabled_metric.value
    }
  }
}
