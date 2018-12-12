# Azure Cloud Seal
Example of Vault Cloud Seal with Azure Key. 
For this example we will use a local installation of Vault just to test this functionality.

## Caveat
If Vault loses access to the Azure seal, it will work normally, but it won't be able to unseal if sealed or process killed.
If needed, you can migrate to a different seal at any time: https://www.vaultproject.io/docs/concepts/seal.html#seal-migration

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
az ad sp create-for-rbac -n stenio-vault --role Owner --scope /subscriptions/c0a...6ba
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
4. Download and start Vault locally
- Go to https://www.vaultproject.io/downloads.html and download and unzip Vault
- Execute: (you might need to adjust commands for Windows)
```
export VAULT_ADDR=http://127.0.0.1:8200
vault server -config=vault_config &
vault operator init -stored-shares=1 -recovery-shares=1 -recovery-threshold=1 
# Output:
# Recovery Key 1: 5jocoSL9....nTlc+Te+utdk=
#
# Initial Root Token: 123nN....AvcZex
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
export VAULT_TOKEN=123nN....AvcZex
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
9. To migrate to a different seal:
```
# Check https://www.vaultproject.io/docs/concepts/seal.html#seal-migration
vault operator unseal -migrate
```