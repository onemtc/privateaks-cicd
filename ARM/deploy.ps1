# Powershell
$ErrorActionPreference="Stop"
$RG="privateaks"
$AKS="aksCluster1"
$LOCATION="EastUS2"
$SSHKEYFILE="akslabkey1"
$DEPLOYBASTION="true"  # change to false if you do not want to deploy Azure Bastion
$DEPLOYPOLICY="true"

# create ssh file if it does not already exist
If (-Not (Test-Path -Path .\$SSHKEYFILE )) { 
    ssh-keygen -f $SSHKEYFILE
 }
$SSHPUBKEY = Get-Content .\$SSHKEYFILE.pub

az group create --name $RG --location $LOCATION
az deployment group create --resource-group $RG  -n aksdeploy --template-file azuredeploy.json `
    --parameters sshpubkey=$SSHPUBKEY deploybastion=$DEPLOYBASTION

$AKSid=$(az aks show -n $AKS -g $RG --output tsv --query id)
echo "==========================="
echo ">>>>>   You will need to copy this Service Principal information into a GitHub Secret -- see instructions"
echo "==========================="
az ad sp create-for-rbac --sdk-auth --scope $AKSid --output json

#####  Set Policy to disallow external IP's on AKS Load Balancers
##### See https://github.com/Azure/azure-policy/blob/master/built-in-policies/policyDefinitions/Kubernetes/LoadbalancerNoPublicIPs.json
echo "==========================="
echo ">>>>>   This Section is Optional -- it will set an Azure Policy to disallow external IP's on AKS Load Balancers"
echo "==========================="
# Enable the policy add-on
az aks enable-addons --addons azure-policy --name $AKS --resource-group $RG
$PolicyID="3fc4dc25-5baf-40d8-9b05-7fe74c1bc64e"  # This is the guid for the Azure policy
az policy assignment create --name 'aks-internal-lb-only' --display-name 'Only allow aks internal lb' --scope $AKSID  --policy $PolicyID