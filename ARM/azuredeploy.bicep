param buildhostname string = 'ghagent'
param uservmname string = 'uservm'
param sshpubkey string = 'changeme'
param aksDnsPrefix string = 'privdns'

param vnetname string = 'labvnet'
param vmsubnetname string = 'vmsubnet'
param akssubnetname string = 'akssubnet'
param usersubnetname string = 'usersubnet'
param aksClusterName string = 'aksCluster1'
param nodesize string = 'Standard_DS2_v2'

@description('Use ephemeral or disk')
@allowed([
  'Ephemeral'
  'Managed'
])
param osDiskType string = 'Ephemeral'

@description('Size of OS disk')
param osDiskSizeGB int = 80
param vmsize string = 'Standard_D2s_v3'
param vmusername string = 'azureuser'
@secure()
param winpwd string 
param vmCustomData string = base64(join([
  '#!/bin/bash'
  'usermod -aG docker ${vmusername}'
  'az aks install-cli'
  '\n'
],'\n'))

param deploybastion bool = false
param publicIpAddressName string = 'bastionpip'

// Use dsvm for build vm image as it has most tools preinstalled
// get image info: az vm image list-offers -l EastUS2 -p microsoft-dsvm -o table
var dsvmimage = {
  publisher: 'microsoft-dsvm'
  offer: 'ubuntu-2004'
  sku: '2004-gen2'
  version: 'latest'
}
var ubuvmimage = {
  publisher: 'Canonical'
  offer: 'UbuntuServer'
  sku: '18.04-LTS'
  version: 'latest'
}

var win11image = {
    publisher: 'microsoftwindowsdesktop'
    offer: 'windows-11'
    sku: 'win11-22h2-pro'
    version: 'latest'
}

//var Owner = '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/8e3af657-a8ff-443c-a75c-2fe8c4bcb635'
//var Contributor = '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c'
//var Reader = '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7'

var akssubnetid = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetname, akssubnetname)
var vmsubnetid = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetname, vmsubnetname)

resource vnet_internal 'Microsoft.Network/virtualNetworks@2019-11-01' = {
  name: vnetname
  location: resourceGroup().location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: vmsubnetname
        properties: {
          addressPrefix: '10.0.0.0/24'
        }
      }
      {
        name: akssubnetname
        properties: {
          addressPrefix: '10.0.1.0/24'
        }
      }
      {
        name: usersubnetname
        properties: {
          addressPrefix: '10.0.2.0/24'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.0.10.0/24'
        }
      }
    ]
  }
  resource vmsubnet 'subnets' existing = {
    name: vmsubnetname
  }
  resource akssubnet 'subnets' existing = {
    name: akssubnetname
  }
  resource usersubnet 'subnets' existing = {
    name: usersubnetname
  }
}



/////// GHAgent VM
resource buildhostname_nic 'Microsoft.Network/networkInterfaces@2019-11-01' = {
  name: '${buildhostname}-nic'
  location: resourceGroup().location
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetname, vmsubnetname)
          }
        }
      }
    ]
  }
  dependsOn: [
    vnet_internal
  ]
}

resource buildvm  'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name: buildhostname
  location: resourceGroup().location
  properties: {
    hardwareProfile: {
      vmSize: vmsize
    }
    osProfile: {
      computerName: buildhostname
      adminUsername: vmusername
      customData: vmCustomData
      linuxConfiguration: {
        ssh: {
          publicKeys: [
            {
              keyData: sshpubkey
              path: '/home/${vmusername}/.ssh/authorized_keys'
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: dsvmimage
      osDisk: {
        name: '${buildhostname}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: buildhostname_nic.id
        }
      ]
    }
  }
}

// User VM
resource uservm_nic 'Microsoft.Network/networkInterfaces@2019-11-01' = {
  name: '${uservmname}-nic'
  location: resourceGroup().location
  properties: {
    ipConfigurations: [
      {
        name: 'ipConfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetname, vmsubnetname)
          }
        }
      }
    ]
  }
  dependsOn: [
    vnet_internal
  ]
}

resource uservm  'Microsoft.Compute/virtualMachines@2022-08-01' = {
  name: uservmname
  location: resourceGroup().location
  properties: {
    hardwareProfile: {
      vmSize: vmsize
    }
    osProfile: {
      computerName: uservmname
      adminUsername: vmusername
      adminPassword: winpwd
      //customData: vmCustomData
      
    }
    storageProfile: {
      imageReference: win11image
      osDisk: {
        name: '${uservmname}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: uservm_nic.id
        }
      ]
    }
  }
}


resource aksCluster 'Microsoft.ContainerService/managedClusters@2022-09-02-preview' = {
  name: aksClusterName
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    apiServerAccessProfile: {
      enablePrivateCluster: true
    }
    dnsPrefix: aksDnsPrefix
    networkProfile: {
      networkPlugin: 'azure'
      serviceCidr: '192.168.128.0/23'
      podCidr: '192.168.0.0/22'
      dnsServiceIP: '192.168.128.10'
      dockerBridgeCidr: '192.168.253.1/24'
    }
    agentPoolProfiles: [
      {
        name: 'nodepool'
        count: 1
        vmSize: nodesize
        osType: 'Linux'
        mode: 'System'
        osDiskType: osDiskType
        osDiskSizeGB: osDiskSizeGB
        vnetSubnetID: akssubnetid
      }
    ]
    linuxProfile: {
      adminUsername: vmusername
      ssh: {
        publicKeys: [
          {
            keyData: sshpubkey
          }
        ]
      }
    }
  }
}

// resource roleNameGuid_resource 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   scope: vnet_internal::akssubnet 
//   name: guid(aksCluster.id,'Contributor')

//   properties: {
//     roleDefinitionId: 'Contributor'
//     //principalId: reference(aksCluster.id, '2020-09-01', 'Full').identity.principalId
//     principalId: aksCluster.identity.principalId
//     description: 'Provide contributor access to AKS MSI'
//   }
// }

resource DemoBastion 'Microsoft.Network/bastionHosts@2020-04-01' = if (deploybastion) {
  name: 'DemoBastion'
  location: resourceGroup().location
  properties: {
    ipConfigurations: [
      {
        id: 'string'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetname, 'AzureBastionSubnet')
          }
          publicIPAddress: {
            id: publicIpAddress.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
        name: 'ipconfig1'
      }
    ]
  }
}

resource publicIpAddress 'Microsoft.Network/publicIpAddresses@2019-02-01' = if (deploybastion) {
  name: publicIpAddressName
  location: resourceGroup().location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

output aksname string = aksClusterName
output aksid string = aksCluster.id
output aksmsi string = reference(aksCluster.id, '2020-09-01', 'Full').identity.principalId
