# Azure Authentication Method
Example of Vault Azure Authentication method

Note: The instructions below are missing a step of granting additional permissions to the VM, you will get an error:
```
"vm principal id is empty"
```
When attempting to login to Vault. Working to identify the resolution.

## Requirements
### Service Principal
For this example, we will use a Azure Service account as described here - https://www.terraform.io/docs/providers/azurerm/authenticating_via_service_principal.html 

Either execute the instructions or set environment variables: 
ARM_SUBSCRIPTION_ID - The ID of the Azure Subscription in which to run the Acceptance Tests.
ARM_CLIENT_ID - The Client ID of the Service Principal.
ARM_CLIENT_SECRET - The Client Secret associated with the Service Principal.
ARM_TENANT_ID - The Tenant ID to use.

### Configuration Steps
#### Azure
1. Generate Azure Service Principal
```
az ad sp create-for-rbac -n stenio-vault --role Owner --scope /subscriptions/c0a6...6ba
export AZURE_TENANT_ID=
export AZURE_CLIENT_ID-=
export AZURE_CLIENT_SECRET= 
```
2. Now go to Azure UI (not available as Terraform resource yet - https://github.com/terraform-providers/terraform-provider-azurerm/issues/2459) 
```
Click on search at the top right and search for "App Registrations"

Change the filter to "All apps"

Search for the app name (vault-admin in the above example), and click on it

Click on "Settings > Required Permissions > Add > Select API > Microsoft Graph" 

Select required permissions

Click on Save

Click on "Grant Permissions"

```
3. Alternatively, if you can find the API id and Permission ID, you can use the Azure CLI: https://docs.microsoft.com/en-us/cli/azure/ad/app/permission?view=azure-cli-latest#az-ad-app-permission-add
###

#### Vault
For the Vault commands, ensure you have:
- Vault binary
- export VAULT_ADDR
- export VAULT_TOKEN

1. Enable auth method
```
vault auth enable azure
```
2. Configure
```
# Note that "resource" must be a resource id visible to the VM. You can use the Service Principal app_id you created for Vault in the above steps
vault write auth/azure/config \
    tenant_id=0e3...c52ec \
    resource=AZURE_APP_ID \
    client_id=f2fbd...b4e \
    client_secret=a7545...48135c
```
3. (Optional) Create Vault ACL policy
```
cat <<POLICY | tee azure-policy.hcl
path "secret/azure/*" {
  capabilities = ["create", "update", "read", "delete"]
}
POLICY
vault policy-write azure azure-policy.hcl
```
4. Create a role.
Here you can associate a Vault policy to:
- bound_resource_group_names 
- bound_service_principal_ids
- bound_group_ids 
- bound_location
- bound_subscription_ids 
- bound_scale_sets 
You don't need to set all, you have flexibility on how restrictive you want to be accepting login requests.
```
vault write auth/azure/role/azure-role \
    policies="azure" \
    bound_resource_group_names=StenioResourceGroup 
```

### Authentication Steps
Now it is time to authenticate!

#### Using Vault Agent
Vault Agent allows you to standardize auth steps regardless of platform. More info https://www.vaultproject.io/docs/agent/index.html
1. Create a VM in Azure
```
az group create --name StenioResourceGroup --location westus
az vm create \
  --resource-group StenioResourceGroup \
  --name StenioVM \
  --image UbuntuLTS \
  --admin-username azureuser \
  --generate-ssh-keys
```
2. Create a Managed Identity and assign to the VM:
```
- In the Azure UI, on the top search bar, type "Managed Identities"
- Click Add, enter name (stenio-identity for example), select location close to you (uswest for example) and save
- Press "refresh" to see your new identity
- Go back to your Virtual Machine
- Select your virtual machine, click on "Identity"
- Click "add" and select your new identity 
```

2. Install Vault Agent 
```
ssh azureuser@PUBLIC_IP_OF_VM
wget https://releases.hashicorp.com/vault/1.0.0/vault_1.0.0_linux_amd64.zip
sudo apt install unzip
unzip vault_1.0.0_linux_amd64.zip vault

# Check that it is working
./vault -v
./vault agent -h
```
3. Still in the VM, create config file 
```
# Here, the "resource" should match what you defined when creating the Vault role. 
# For example, if you used "AZURE_APP_ID" in the role, here you should have the same AZURE_APP_ID in this field.

cat <<CONFIG | tee vault-agent.hcl
pid_file = "./pidfile"

auto_auth {
        method "azure" {
                config = {
                        role = "azure-role"
                        resource = "AZURE_APP_ID"
                }
        }

        sink "file" {
                config = {
                        path = "/tmp/.vault-token"
                }
        }
}
CONFIG
```
4. Run the agent as a background process
```
./vault agent -config=vault-agent.hcl &
```
5. Validate token present
```
cat /tmp/.vault-token
```
#### Manual (script)
If you prefer, or to understand what Vault Agent is doing behind the scenes, you can also authenticate manually:

1. Get JWT token from instance metadata
```
# Ensure you are inside the Azure vm
# Replace AZURE_APP_ID with the value used when configuring Vault
curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=AZURE_APP_ID' -H Metadata:true -s
```
2. Send a request to Vault
```
# Create a login payload:
cat <<PAYLOAD | tee vault-agent.hcl
{
    "role": "azure-role",
    "jwt": "JWT_TOKEN_FROM_METADATA",
    "subscription_id": "c0...56ba",
    "resource_group_name": "StenioResourceGroup",
    "vm_name": "StenioVM"
}
PAYLOAD

# Ensure you have your Vault address. 
# You might need to deploy Vault in a remote machine anywhere accessible by internet and open port 8200:
curl \
    --request POST \
    --data @payload.json \
    $VAULT_ADDR/v1/auth/azure/login
```


6. If you prefer, you can do the authentication without using Vault
```
curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=AZURE_APP_ID' -H Metadata:true -s
cat <<PAYLOAD | tee payload.json
 {
    "role": "azure-role",
    "jwt": "eyJ0...m7w",
    "subscription_id": "c0a60...ba",
    "resource_group_name": "StenioResourceGroup",
    "vm_name": "StenioVM"
}
PAYLOAD
