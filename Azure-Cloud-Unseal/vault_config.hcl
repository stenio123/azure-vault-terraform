storage "file" {
     path = "/Users/stenio/Projects/Hashicorp/azure-vault-terraform/Azure-Cloud-Unseal/data"
}

listener "tcp" {
  address     = "127.0.0.1:8200"
  tls_disable = 1
}

seal "azurekeyvault" {
  # tenant_id      = "AZURE_TENANT_ID" 
  # client_id      = "AZURE_CLIENT_ID"
  # client_secret  = "AZURE_CLIENT_SECRET"
  # vault_name     = "VAULT_AZUREKEYVAULT_VAULT_NAME"
  # key_name       = "VAULT_AZUREKEYVAULT_KEY_NAME"
}