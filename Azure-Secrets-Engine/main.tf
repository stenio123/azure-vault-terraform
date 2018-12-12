terraform {
  required_version = ">= 0.11.0"
}

# Configure the Azure Provider
provider "azurerm" {}

data "azurerm_subscription" "primary" {}

# Register app (creates user for Vault)
resource "azurerm_azuread_application" "vault-app" {
  name                       = "hug-demo-vault-admin"
}

# Creates Service Principal
resource "azurerm_azuread_service_principal" "vault-service-principal" {
  application_id = "${azurerm_azuread_application.vault-app.application_id}"
}

# Creates custom role
resource "azurerm_role_definition" "vault-secrets-engine" {
  #role_definition_id = "00000000-0000-0000-0000-000000000000"
  name               = "vault-secrets-engine"
  scope              = "${data.azurerm_subscription.primary.id}"

  permissions {
    actions     = ["Application.ReadWrite.All","Directory.ReadWrite.All","*"]
    data_actions = ["*"]
  }

  assignable_scopes = [
    "${data.azurerm_subscription.primary.id}",
  ]
}

# Assigns custom role
resource "azurerm_role_assignment" "test" {
  scope                = "${data.azurerm_subscription.primary.id}"
  role_definition_id = "${azurerm_role_definition.vault-secrets-engine.id}"
  principal_id         = "${azurerm_azuread_service_principal.vault-service-principal.id}"
}
