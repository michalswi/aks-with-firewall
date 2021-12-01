resource "azurerm_resource_group" "frg" {
  name     = "${var.name}-fw-rg"
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
  address_prefixes     = ["10.10.1.0/24"]
}

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
