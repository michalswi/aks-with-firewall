
variable "client_id" {}
variable "client_secret" {}

variable rg_name {
    default = "msfwrg"
}

variable location {
    default = "westeurope"
}

variable fw_name {
    default = "msfw"
}

# todo
variable "dns_prefix" {
    default = "testms"
}