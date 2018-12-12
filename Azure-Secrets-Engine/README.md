# Azure with Vault and Terraform
Example of workflows using Azure, Vault and Terraform

## Requirements
### Service Principal
For this example, we will use a Azure Service account as described here - https://www.terraform.io/docs/providers/azurerm/authenticating_via_service_principal.html 

Either execute the instructions or set environment variables: 
ARM_SUBSCRIPTION_ID - The ID of the Azure Subscription in which to run the Acceptance Tests.
ARM_CLIENT_ID - The Client ID of the Service Principal.
ARM_CLIENT_SECRET - The Client Secret associated with the Service Principal.
ARM_TENANT_ID - The Tenant ID to use.

### Terraform
1. Download Terraform https://www.terraform.io/downloads.html
2. Unzip 
3. Clone this repository
```
git clone THIS-REPO
cd THIS-REPO
```

### Hashicorp Vault
Standing up and unsealing a Vault server is outside the scope of this guide. Instructions can be found here https://github.com/hashicorp/vault-guides/tree/master/operations/provision-vault

... but if you really want, you can start a quick dev server in your local machine:
1. Download Vault https://www.vaultproject.io/downloads.html
2. Unzip and run
```
# Run Vault in the background, in dev mode
vault server -dev -dev-root-token-id="root" &
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root
```


## Azure Secret Engine
### Azure:
To configure and enable the Azure Service principal used by Vault:
1. Execute:
```
cd azure-secret-engine-demo
export ARM_SUBSCRIPTION_ID
export ARM_CLIENT_ID
export ARM_CLIENT_SECRET
export ARM_TENANT_ID
terraform init
terraform plan
# This will show the expected output - it will create an application, a service principal and associate a role in Azure.
terraform apply 
``` 
2. Now go to Azure UI (not available as Terraform resource yet - https://github.com/terraform-providers/terraform-provider-azurerm/issues/2459) 
```
Click on search at the top right and search for "App Registrations"

Change the filter to "All apps"

Search for the app name (vault-admin in the above example), and click on it

Click on "Settings > Required Permissions > Add > Select API > Windows Azure Active Directory" (if not grayed out)

Click on "Windows Azure Active Directory" and check the permissions:

Read and Write directory data
Read and Write all applications
Click on Save

Click on "Grant Permissions"

```
3. Alternatively, if you can find the API id and Permission ID, you can use the Azure CLI: https://docs.microsoft.com/en-us/cli/azure/ad/app/permission?view=azure-cli-latest#az-ad-app-permission-add

### Vault
1. Enable Secret Engine
```
# Create config file
{
  "type": "azure",
}

curl     --header "X-Vault-Token: $VAULT_TOKEN"     --request POST     --data @payload.json     $VAULT_ADDR/v1/sys/mounts/azure
```
2. Configure Secret Engine
```
# Create config file
{
  "subscription_id": "94ca80...",
  "tenant_id": "d0ac7e...",
  "client_id": "e607c4...",
  "client_secret": "9a6346...",
  "environment": "AzurePublicCloud"
}

curl     --header "X-Vault-Token: $VAULT_TOKEN"     --request POST     --data @payload.json     $VAULT_ADDR/v1/azure/config
```
3. Create roles
```
# payload.json
{
    "name": "test", 
    "azure_roles": "[{ \"role_name\": \"Contributor\" ,\"scope\": \"/subscriptions/YOUR-SUBSCRIPTION-ID\"}]" 
}

# Configure Azure user with this role
 curl     --header "X-Vault-Token: $VAULT_TOKEN"      --request POST     --data @payload.json     $VAULT_ADDR/v1/azure/roles/test-role

# Create user and retrieve creds
curl     --header "X-Vault-Token: $VAULT_TOKEN"      --request GET    $VAULT_ADDR/v1/azure/creds/test-role 

# Output
{
  "request_id": "2f9d37b4-502d-b80f-8242-e455fa3cd1c1",
  "lease_id": "azure/creds/test-role/2orH1EXH2k6fA8xoWVjy0Jml",
  "renewable": true,
  "lease_duration": 2764800,
  "data": {
    "client_id": "xxx",
    "client_secret": "xxx"
  },
  "wrap_info": null,
  "warnings": null,
  "auth": null
}

# User will have the "vault-" prefix. 
# You can see this user on Azure by issuing the command:
az ad sp list --query "[?contains(appId, 'GENERATED-CLIENT-ID')]"
```

