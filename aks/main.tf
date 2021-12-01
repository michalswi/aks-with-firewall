resource "azurerm_resource_group" "k8s" {
  name     = "${var.name}-k8s-rg"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.name}-vnet"
  location            = azurerm_resource_group.k8s.location
  resource_group_name = azurerm_resource_group.k8s.name
  address_space       = ["10.20.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.name}-subnet"
  resource_group_name  = azurerm_resource_group.k8s.name
  address_prefixes     = ["10.20.2.0/24"]
  virtual_network_name = azurerm_virtual_network.vnet.name
}

resource "azurerm_role_assignment" "vnet_permissions_aci" {
  principal_id         = azurerm_kubernetes_cluster.k8s.identity[0].principal_id
  scope                = azurerm_virtual_network.vnet.id
  role_definition_name = "Network Contributor"
}

resource "azurerm_kubernetes_cluster" "k8s" {
  name                = "${var.name}-k8s"
  location            = azurerm_resource_group.k8s.location
  resource_group_name = azurerm_resource_group.k8s.name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name           = "agentpool"
    node_count     = var.agent_count
    vm_size        = "Standard_B2s"
    vnet_subnet_id = azurerm_subnet.subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = var.network_plugin
  }

  role_based_access_control {
    enabled = true
  }

  tags = {
    Environment = "dev"
  }

  provisioner "local-exec" {
    command = "./run.sh"
    environment = {
      K8S_NAME = "${var.name}-k8s"
      K8S_RG   = "${var.name}-k8s-rg"
    }
  }
}
