provider "azurerm" {
  features {}
  subscription_id = ""
  tenant_id       = ""

}

#variable "tenant_id" {
#  description = "The Tenant ID for the Azure subscription"
#  type        = string
#}

variable "location" {
  description = "The Azure region to deploy resources"
  type        = string
  default     = "Canada Central"
}

resource "azurerm_resource_group" "aks_rg" {
  name     = "aks-resource-group"
  location = var.location
}

resource "azurerm_virtual_network" "aks_vnet" {
  name                = "aks-vnet"
  address_space       = ["10.0.0.0/8"]
  location            = var.location
  resource_group_name = azurerm_resource_group.aks_rg.name
}

resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.aks_rg.name
  virtual_network_name = azurerm_virtual_network.aks_vnet.name
  address_prefixes     = ["10.240.0.0/16"]
}

resource "azurerm_storage_account" "backup_storage" {
  name                     = "aksbackupstorage${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.aks_rg.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_storage_container" "backup_container" {
  name                  = "aks-backup-container"
  storage_account_name  = azurerm_storage_account.backup_storage.name
  container_access_type = "private"
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "myAKSCluster"
  location            = var.location
  resource_group_name = azurerm_resource_group.aks_rg.name
  dns_prefix          = "myaks"
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  default_node_pool {
    name       = "agentpool"
    node_count = 3
    vm_size    = "Standard_DS2_v2"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  linux_profile {
    admin_username = "azureuser"

    ssh_key {
      key_data = file("${path.module}/id_rsa.pub")  # Ruta relativa al archivo en el mismo directorio
    }
  }

  tags = {
    Environment = "Dev"
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "additional_pool" {
  name                  = "addpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  vm_size               = "Standard_DS2_v2"
  node_count            = 1
  vnet_subnet_id        = azurerm_subnet.aks_subnet.id
}

resource "azurerm_data_protection_backup_vault" "backup_vault" {
  name                = "exampleBackupVault"
  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = var.location
  datastore_type      = "VaultStore"
  redundancy          = "GeoRedundant"
  
  identity {
    type = "SystemAssigned"
  }
}

#Seccion para habilitar la extesión de BK en el AKS - presenta fallas
#resource "azurerm_kubernetes_cluster_extension" "backup_extension" {
#  name                    = "aks-backup-extension"
#  cluster_id              = azurerm_kubernetes_cluster.aks.id
#  extension_type          = "microsoft.dataprotection.kubernetes"
#  release_train           = "stable"
#
#configuration_settings = {
#    "configuration.backupStorageLocation.config.storageAccount" = azurerm_storage_account.backup_storage.name
#    "configuration.backupStorageLocation.bucket"                = azurerm_storage_container.backup_container.name
#  }
#}
