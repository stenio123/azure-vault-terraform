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

### Steps
1. Generate Azure Service Principal
```
az ad sp create-for-rbac -n stenio-vault --role Owner --scope /subscriptions/c0a607b2-6372-4ef3-abdb-dbe52a7b56ba
export AZURE_TENANT_ID=
export AZURE_CLIENT_ID-=
export AZURE_CLIENT_SECRET= 
```
2. Create Azure Vault Key
```
az group create -n 'StenioResourceGroup' -l westus
az provider register -n Microsoft.KeyVault
az keyvault create --name 'StenioKeyVault' --resource-group 'StenioResourceGroup' --location westus
az keyvault key create --vault-name 'StenioKeyVault' --name 'StenioFirstKey' --protection software
```
3. Update permissions!
```
Go to app registrations, select service principal, click "permissions", select API, Azure.KeyVault, grant permission to use, save, press "grant"
Go to Azure Key Vault, select vault, click permissions, add service principal, grant permissions, press "Save"
```
4. Start Vault
```
export VAULT_ADDR=http://127.0.0.1:8200
vault server -config=vault_config &
vault operator init -stored-shares=1 -recovery-shares=1 -recovery-threshold=1 -key-shares=1 -key-threshold=1
# Output:
# Recovery Key 1: 5jocoSL95C/dbrL1rnlVyLHVQxOBZt8nTlc+Te+utdk=
#
# Initial Root Token: 123nNANuMHj2K9Cq3IAvcZex
#
# Success! Vault is initialized

# and vault status
#Key                      Value
# ---                      -----
# Recovery Seal Type       shamir
# Sealed                   false
# Total Recovery Shares    1
# Threshold                1
# Version                  0.11.0-beta1+ent
# Cluster Name             vault-cluster-986344a8
# Cluster ID               c75eb849-7bf3-c39f-8c64-630e55bcbca1
# HA Enabled               false
```
5. Login as root
```
# Note: it is not best practice to operate with the root token, create an admin user instead!
export VAULT_TOKEN=123nNANuMHj2K9Cq3IAvcZex
```
6. Seal Vault
```
vault operator seal
vault status

# Output: it is sealed!
```
7. Unseal Vault
```
vault operator unseal
# You will be prompted for the recovery key(s)
```
8. Kill and restart Vault process
```
ps aux | grep vault
kill -9 VAULT_PID
vault server -config=vault_config.hcl &

# Output:
# ...
# ==> Vault server started! Log data will stream in below:
#
# 2018-12-11T18:19:49.691-0600 [INFO ] core: stored unseal keys supported, attempting fetch
# 2018-12-11T18:19:49.882-0600 [INFO ] core: vault is unsealed
# 2018-12-11T18:19:49.882-0600 [INFO ] core: post-unseal setup starting
# 2018-12-11T18:19:50.379-0600 [INFO ] core: loaded wrapping token key
...
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

