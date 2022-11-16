#!/bin/bash
set -e   # stop on error
#RG="privateaks"
GITHUBREPOURL="https://github.com/expNYCLarryClaman/privateaks"
RG="EXP-NY-SDBX-RG"
AKS="aksCluster1"
LOCATION="WestUS3"
SSHKEYFILE="akslabkey"
DEPLOYBASTION="true" # change to false if you do not want to deploy Azure Bastion
#SSHPUBKEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDlDHE6NsyOYy53U1G5zG3NbTdJOD54zrdcEdwYTJOTmIEkpfmSUjD/gIKgoM3s5vBfs/SeWCO8hQ/WxSDYYneJhldBmw40dg0n/tCDH7/5xrrwqhs3obKqkQ3R2ZwUTaHMkKkQx4fyZ/5SD+ii1IqxnyNnpvHIUib2yw2lhlGLuye+t65JlsNAYAo6sHaCe5Sdb1jFuOK79YF8mgfIKe6O3/evBFJMZ+TJ9yJXwyRBojL8k3xpXiJtSpOuZHIXVu+FesN/gWOUyLb3tua3uwK0NhmK84pTFFUB/fkQimGmfsFcv9hRh8PIIWIDq1FlhZkJubb1prWmMO374t6HvVuz"
#WINPWD="changeme"


# create ssh key file if it does not already exist
if [ ! -f $SSHKEYFILE ]; then
    ssh-keygen -f $SSHKEYFILE
fi
SSHPUBKEY=$(cat "$SSHKEYFILE.pub")

az group create --name $RG --location $LOCATION

# get github token for self-hosted runner registration  https://docs.github.com/en/rest/actions/self-hosted-runners#create-a-registration-token-for-a-repository
# Note: must be logged into the gh client prior to running this
# Note: Token is only good for 60 minutes
REPO=$(echo $GITHUBREPOURL|awk -F'github.com' '{print $2}')
gh api --method POST   -H "Accept: application/vnd.github+json"  "/repos${REPO}/actions/runners/registration-token"



az deployment group create --resource-group $RG  -n aksdeploy --template-file azuredeploy.bicep \
    --parameters sshpubkey="$SSHPUBKEY" winpwd="$WINPWD" deploybastion=$DEPLOYBASTION


AKSid=$(az aks show -n $AKS -g $RG --output tsv --query id)
echo "==========================="
echo ">>>>>  You will need to copy this Service Principal information into a GitHub Secret -- see instructions"
echo "==========================="
SP=$(az ad sp create-for-rbac --name lnc-privateaks --sdk-auth --role Reader --scopes $AKSid --output json)
echo $SP |jq



#####  Set Policy to disallow external IP's on AKS Load Balancers
##### See https://github.com/Azure/azure-policy/blob/master/built-in-policies/policyDefinitions/Kubernetes/LoadbalancerNoPublicIPs.json
echo "==========================="
echo ">>>>>   This Section is Optional -- it will set an Azure Policy to disallow external IP's on AKS Load Balancers"
echo "==========================="
# Enable the policy add-on
az aks enable-addons --addons azure-policy --name $AKS --resource-group $RG
$PolicyID="3fc4dc25-5baf-40d8-9b05-7fe74c1bc64e"  # This is the guid for the Azure policy
az policy assignment create --name 'aks-internal-lb-only' --display-name 'Only allow aks internal lb' --scope $AKSID  --policy $PolicyID
