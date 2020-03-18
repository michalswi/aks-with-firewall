resource "azurerm_resource_group" "frg" {
    name     = var.rg_name
    location = var.location
}

resource "azurerm_virtual_network" "fvnet" {
  name                = "${var.fw_name}-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.frg.location
  resource_group_name = azurerm_resource_group.frg.name
}

resource "azurerm_subnet" "fsubnet" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.frg.name
  virtual_network_name = azurerm_virtual_network.fvnet.name
  address_prefix       = "10.10.1.0/24"
}

# https://www.terraform.io/docs/providers/azurestack/r/public_ip.html
resource "azurerm_public_ip" "fip" {
  name                = "${var.fw_name}-ip"
  location            = azurerm_resource_group.frg.location
  resource_group_name = azurerm_resource_group.frg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = var.dns_prefix
}

resource "azurerm_firewall" "firewall" {
  name                = var.fw_name
  location            = azurerm_resource_group.frg.location
  resource_group_name = azurerm_resource_group.frg.name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.fsubnet.id
    public_ip_address_id = azurerm_public_ip.fip.id
  }
}

# https://www.terraform.io/docs/providers/azurerm/r/firewall_nat_rule_collection.html

# resource "azurerm_firewall_nat_rule_collection" "fnat" {
#   name                = "testcollection"
#   azure_firewall_name = azurerm_firewall.firewall.name
#   resource_group_name = azurerm_resource_group.frg.name
#   priority            = 100
#   action              = "Dnat"

#   rule {
#     name = "testrule"

#     source_addresses = [
#       "*",
#     ]

#     destination_ports = [
#       "80",
#     ]

#     destination_addresses = [
#       "8.8.8.8",
#       "8.8.4.4",
#     ]

#     protocols = [
#       "TCP",
#       "UDP",
#     ]

#   translatedAddress = "10.0.105.64",
#   translatedPort = "80"
#   }
# }