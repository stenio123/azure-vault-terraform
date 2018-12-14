# Azure Authentication Method
Example of Vault Azure Authentication method

## Requirements
- Azure CLI installed
- Vault unsealed and running
- jq https://stedolan.github.io/jq/download/

### Configuration Steps
#### Azure
1. Determine your Azure subscription id
```
AZURE_SUBSCRIPTION=$(az account show | jq -r .id)
```
2. Create Azure role with minimal permissions
```
az role definition create --role-definition '{ "Name": "Vault Auth - ReadOnly", "Description": "Access VM information to authenticate VMs with vault.", "Actions": [ "Microsoft.Compute/virtualMachines/*/read", "Microsoft.Compute/virtualMachineScaleSets/*/read"], "AssignableScopes": ["/subscriptions/$AZURE_SUBSCRIPTION"]}
```
3. Generate Azure Service Principal
```
AZURE_APP_CREDS=$(az ad sp create-for-rbac -n "vault-test" \
  --role “Vault Auth - ReadOnly” \
  --years 3 \
  --scopes /subscriptions/$AZURE_SUBSCRIPTION)

# Configure environment variables:
export AZURE_TENANT_ID=$(echo $AZURE_APP_CREDS | jq .tenant)
export AZURE_CLIENT_ID=$(echo $AZURE_APP_CREDS | jq .appId)
export AZURE_CLIENT_SECRET= $(echo $AZURE_APP_CREDS | jq .password)
```

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
# Note that "resource" must be a resource id visible to the VM. You can use the example string or Service Principal app_id you created for Vault in the above steps. Make sure you use the same resource on the client side!
vault write auth/azure/config \
    tenant_id=$AZURE_TENANT_ID \
    resource="https://management.azure.com" \
    client_id=$AZURE_CLIENT_ID \
    client_secret=$AZURE_CLIENT_SECRET
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
    bound_resource_group_names=StenioResourceGroup \
    bound_subscription_ids=$AZURE_SUBSCRIPTION 
```

### Authentication Steps
Now it is time to authenticate!

#### Using Vault Agent
Vault Agent allows you to standardize auth steps regardless of platform, and it will manage token lifecycle in the background. 
More info https://www.vaultproject.io/docs/agent/index.html
1. Create a VM in Azure
```
az group create --name StenioResourceGroup --location westus
az vm create \
  --resource-group StenioResourceGroup \
  --name StenioVM \
  --image UbuntuLTS \
  --admin-username azureuser \
  --generate-ssh-keys
  --assign-identity

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
                        resource = "https://management.azure.com"
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
# If desired, you can replace the "resource" field with the value used when configuring Vault
curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://management.azure.com' -H Metadata:true -s
```
2. Send a request to Vault
```
# Create a login payload:
cat <<PAYLOAD | tee vault-agent.hcl
{
    "role": "azure-role",
    "jwt": "JWT_TOKEN_FROM_METADATA",
    "subscription_id": "SUBSCRIPTION_ID_FROM_METADATA",
    "resource_group_name": "RESOURCE_GROUP_FROM_METADATA",
    "vm_name": "VM_NAME_FROM_METADATA"
}
PAYLOAD

# Ensure you have your Vault address. 
# You might need to deploy Vault in a remote machine anywhere accessible by internet and open port 8200:
curl \
    --request POST \
    --data @payload.json \
    $VAULT_ADDR/v1/auth/azure/login
```
