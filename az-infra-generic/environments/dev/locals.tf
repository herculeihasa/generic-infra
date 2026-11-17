locals {
  # Naming convention: <abbreviation>-<project>-<environment>-<region code>
  # (Microsoft Cloud Adoption Framework abbreviations).
  location_abbreviations = {
    francecentral      = "frc"
    francesouth        = "frs"
    westeurope         = "weu"
    northeurope        = "neu"
    germanywestcentral = "gwc"
    switzerlandnorth   = "chn"
    belgiumcentral     = "bec"
    uksouth            = "uks"
    swedencentral      = "sdc"
    eastus             = "eus"
    eastus2            = "eus2"
  }
  location_short = lookup(local.location_abbreviations, var.location, var.location)
  name_suffix    = "${var.project}-${var.environment}-${local.location_short}"

  names = {
    resource_group  = "rg-${local.name_suffix}"
    virtual_network = "vnet-${local.name_suffix}"
    aks_subnet      = "snet-aks-nodes"
    log_analytics   = "log-${local.name_suffix}"
    aks_cluster     = "aks-${local.name_suffix}"
  }

  tags = merge(var.tags, {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
    stack       = "aks"
  })
}
