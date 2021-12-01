variable "name" {
  default = "demo"
}

variable "location" {
  default = "westeurope"
}

variable "dns_prefix" {
  default = "demodns"
}

variable "agent_count" {
  default = 1
}

variable "kubernetes_version" {
  default = "1.19.3"
}

variable "network_plugin" {
  default = "azure"
  # default = "kubenet"
  # default = "flannel"
  # default = "cilium"
}