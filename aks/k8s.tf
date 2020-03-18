
resource "azurerm_resource_group" "k8s" {
    name     = var.rg_name
    location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.cluster_name}-vnet"
  location            = azurerm_resource_group.k8s.location
  resource_group_name = azurerm_resource_group.k8s.name
  address_space       = ["10.20.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.cluster_name}-subnet"
  resource_group_name  = azurerm_resource_group.k8s.name
  address_prefix       = "10.20.1.0/24"
  virtual_network_name = azurerm_virtual_network.vnet.name
}

resource "azurerm_kubernetes_cluster" "k8s" {
    name                = var.cluster_name
    location            = azurerm_resource_group.k8s.location
    resource_group_name = azurerm_resource_group.k8s.name
    dns_prefix          = var.dns_prefix
    kubernetes_version  = var.kubernetes_version

    default_node_pool {
        name            = "agentpool"
        node_count      = var.agent_count
        vm_size         = "Standard_B2s"
        vnet_subnet_id  = azurerm_subnet.subnet.id
    }

    service_principal {
        client_id     = var.client_id
        client_secret = var.client_secret
    }

    network_profile {
        network_plugin = var.network_plugin
    }

    role_based_access_control {
        enabled = true
    }

    tags = {
        Environment = "Development"
    }

    provisioner "local-exec" {
        command = "./run.sh"
        environment = {
            K8S_NAME = var.cluster_name
            K8S_RG   = var.rg_name
        }
    }
}