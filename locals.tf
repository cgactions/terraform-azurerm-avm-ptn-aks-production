locals {
  private_dns_zone_name = try(reverse(split("/", var.private_dns_zone_id))[0], null)
  valid_private_dns_zone_regexs = [
    "private\\.[a-z0-9]+\\.azmk8s\\.io",
    "privatelink\\.[a-z0-9]+\\.azmk8s\\.io",
    "[a-zA-Z0-9\\-]{1,32}\\.private\\.[a-z]+\\.azmk8s\\.io",
    "[a-zA-Z0-9\\-]{1,32}\\.privatelink\\.[a-z]+\\.azmk8s\\.io",
  ]
}

locals {
  default_node_pool_available_zones = setsubtract(local.zones, local.restricted_zones)
  filtered_vms = [
    for sku in data.azapi_resource_list.example.output.value :
    sku if(sku.resourceType == "virtualMachines" && sku.name == var.default_node_pool_vm_sku)
  ]
  restricted_zones = try(local.filtered_vms[0].restrictions[0].restrictionInfo.zones, [])
  zones            = local.filtered_vms[0].locationInfo[0].zones
}

locals {
  filtered_vms_by_node_pool = {
    for pool_name, pool in var.node_pools : pool_name => [
      for sku in data.azapi_resource_list.example.output.value :
      sku if(sku.resourceType == "virtualMachines" && sku.name == pool.vm_size)
    ]
  }
  my_node_pool_zones_by_pool = {
    for pool_name, pool in var.node_pools : pool_name => setsubtract(
      local.filtered_vms_by_node_pool[pool_name][0].locationInfo[0].zones,
      try(local.filtered_vms_by_node_pool[pool_name][0].restrictions[0].restrictionInfo.zones, [])
    )
  }
  zonetagged_node_pools = {
    for pool_name, pool in var.node_pools : pool_name => merge(pool, { zones = local.my_node_pool_zones_by_pool[pool_name] })
  }
}


locals {
  node_pools_map = merge([
    for pool_key, pool_data in local.zonetagged_node_pools : {
      for zone in pool_data.zones :
        "${pool_key}-${zone}" => {
          original_key         = pool_key
          generated_name       = substr("${pool_data.name}${zone}", 0, 12)
          vm_size              = pool_data.vm_size
          orchestrator_version = pool_data.orchestrator_version
          max_count            = pool_data.max_count
          min_count            = pool_data.min_count
          tags                 = pool_data.tags
          labels               = pool_data.labels
          os_sku               = pool_data.os_sku
          mode                 = pool_data.mode
          os_disk_size_gb      = pool_data.os_disk_size_gb
          zone_list            = [zone]
        }
    }
  ]...)
}
locals {
  log_analytics_tables = ["AKSAudit", "AKSAuditAdmin", "AKSControlPlane", "ContainerLogV2"]
}

# Helper locals to make the dynamic block more readable
# There are three attributes here to cater for resources that
# support both user and system MIs, only system MIs, and only user MIs
locals {
  managed_identities = {
    user_assigned = length(var.managed_identities.user_assigned_resource_ids) > 0 ? {
      this = {
        type                       = "UserAssigned"
        user_assigned_resource_ids = var.managed_identities.user_assigned_resource_ids
      }
      } : {
      this = {
        type                       = "UserAssigned"
        user_assigned_resource_ids = azurerm_user_assigned_identity.aks[*].id
      }
    }
  }
}

locals {
  network_resource_group_id = regex("(.*?/resourceGroups/[^/]+)", var.network.node_subnet_id)[0]
}
