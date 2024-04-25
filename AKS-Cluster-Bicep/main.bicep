targetScope = 'subscription'

param rgName string
param clusterName string
param akslaWorkspaceName string
param akslaWorkspaceRGName string
param vnetRgName string
param vnetName string
param subnetName string
param aksuseraccessprincipalId string
param aksadminaccessprincipalId string
param aksIdentityName string
//param kubernetesVersion string
param rtAKSName string
param rtRGName string

param location string = deployment().location
param availabilityZones array
param enableAutoScaling bool
param autoScalingProfile object

param podCidr string //= '172.17.0.0/16'
param upgradeChannel string
param nodeOSUpgradeChannel string

@allowed([
  'Ubuntu'
  'AzureLinux'
])
param osSku string = 'Ubuntu'

param systemNodePoolReplicas int
param userNodePool1Replicas int
param userNodePool2Replicas int
param systemNodePoolSku string
param userNodePool1Sku string
param userNodePool2Sku string

param keyVaultRGName string
param acrRGName string

@allowed([
  'azure'
  'azure-overlay'
  'kubenet'
])
param networkPlugin string = 'kubenet'

param acrName string //User to provide each time
param keyvaultName string //user to provide each time

resource rg 'Microsoft.Resources/resourceGroups@2020-06-01' existing = {
  name: rgName
}

module aksIdentity 'modules/Identity/userassigned.bicep' = {
  scope: rg
  name: aksIdentityName
  params: {
    location: location
    identityName: aksIdentityName
  }
}

module aksPodIdentityRole 'modules/Identity/role.bicep' = {
  scope: rg
  name: 'aksPodIdentityRole'
  params: {
    principalId: aksIdentity.outputs.principalId
    roleGuid: 'f1a07417-d97a-45cb-824c-7a7467783830' //Managed Identity Operator
  }
}


module privatednsAKSZone 'modules/vnet/privatednszone.bicep' = {
  scope: rg
  name: 'privatednsAKSZone'
  params: {
    privateDNSZoneName: 'privatelink.${toLower(location)}.azmk8s.io'
  }
}


resource vnet 'Microsoft.Network/virtualNetworks@2022-09-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetRgName)
}


module privateDNSLinkAKS 'modules/vnet/privatednslink.bicep' = {
  scope: rg
  name: 'privateDNSLinkAKS'
  params: {
    privateDnsZoneName: privatednsAKSZone.outputs.privateDNSZoneName
    vnetId: vnet.id
  }
  dependsOn: [
    privatednsAKSZone
  ]
}


module aksPolicy 'modules/policy/policy.bicep' = {
  scope: resourceGroup(rg.name)
  name: 'aksPolicy'
  params: {
    location: rg.location
  }
}

resource akslaworkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing ={
  scope: resourceGroup(akslaWorkspaceRGName)
  name: akslaWorkspaceName
}

resource aksSubnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  parent: vnet
  name: subnetName
}

module aksCluster 'modules/aks/privateaks.bicep' = {
  scope: rg
  name: 'aksCluster'
  params: {
    autoScalingProfile:autoScalingProfile
    enableAutoScaling: enableAutoScaling
    availabilityZones:availabilityZones
    userNodePool1Sku: userNodePool1Sku
    userNodePool2Sku: userNodePool2Sku
    systemNodePoolSku: systemNodePoolSku
    location: location
    aadGroupdIds: [
      aksadminaccessprincipalId
    ]
    clusterName: clusterName
    userNodePool1Replicas: userNodePool1Replicas
    userNodePool2Replicas: userNodePool2Replicas
    systemNodePoolReplicas: systemNodePoolReplicas
    osSku: osSku
    nodeOSUpgradeChannel:nodeOSUpgradeChannel
    upgradeChannel: upgradeChannel
    //kubernetesVersion: kubernetesVersion
    networkPlugin: networkPlugin
    logworkspaceid: akslaworkspace.id
    privateDNSZoneId: privatednsAKSZone.outputs.privateDNSZoneId
    subnetId: aksSubnet.id
    identity: {
      '${aksIdentity.outputs.identityid}' : {}
    }
    podCidr: podCidr
  }
  dependsOn: [
    aksPvtDNSContrib
    aksPvtNetworkContrib
    aksPodIdentityRole
    aksPolicy
  ]
}

module aksRouteTableRole 'modules/Identity/rtrole.bicep' = {
  scope: resourceGroup(rtRGName)
  name: 'aksRouteTableRole'
  params: {
    principalId: aksIdentity.outputs.principalId
    roleGuid: '4d97b98b-1d4f-4787-a291-c67834d212e7' //Network Contributor
    rtName: rtAKSName
  }
}

module acraksaccess 'modules/Identity/acrrole.bicep' = {
  scope: resourceGroup(acrRGName)
  name: 'acraksaccess'
  params: {
    principalId: aksCluster.outputs.kubeletIdentity
    roleGuid: '7f951dda-4ed3-4680-a7ca-43fe172d538d' //AcrPull
    acrName: acrName
  }
}

module aksPvtNetworkContrib 'modules/Identity/networkcontributorrole.bicep' = {
  scope: resourceGroup(vnetRgName)
  name: 'aksPvtNetworkContrib'
  params: {
    principalId: aksIdentity.outputs.principalId
    roleGuid: '4d97b98b-1d4f-4787-a291-c67834d212e7' //Network Contributor
    vnetName: vnetName
  }
}

module aksPvtDNSContrib 'modules/Identity/pvtdnscontribrole.bicep' = {
  scope: rg
  name: 'aksPvtDNSContrib'
  params: {
    location: location
    principalId: aksIdentity.outputs.principalId
    roleGuid: 'b12aa53e-6015-4669-85d0-8515ebb3ae7f' //Private DNS Zone Contributor
  }
}

module vmContributeRole 'modules/Identity/role.bicep' = {
  scope: resourceGroup('${clusterName}-aksInfraRG')
  name: 'vmContributeRole'
  params: {
    principalId: aksIdentity.outputs.principalId
    roleGuid: '9980e02c-c2be-4d73-94e8-173b1dc7cf3c' //Virtual Machine Contributor
  }
  dependsOn: [
    aksCluster
  ]
}

module aksuseraccess 'modules/Identity/role.bicep' = {
  scope: rg
  name: 'aksuseraccess'
  params: {
    principalId: aksuseraccessprincipalId
    roleGuid: '4abbcc35-e782-43d8-92c5-2d3f1bd2253f' //Azure Kubernetes Service Cluster User Role
  }
}

module aksuseraccessRBAC 'modules/Identity/role.bicep' = {
  scope: rg
  name: 'aksuseraccessRBAC'
  params: {
    principalId: aksuseraccessprincipalId
    roleGuid: '7f6c6a51-bcf8-42ba-9220-52d62157d7db'    //Azure Kubernetes Service RBAC Reader
  }
}

module aksadminaccess 'modules/Identity/role.bicep' = {
  scope: rg
  name: 'aksadminaccess'
  params: {
    principalId: aksadminaccessprincipalId
    roleGuid: '0ab0b1a8-8aac-4efd-b8c2-3ee1fb270be8' //Azure Kubernetes Service Cluster Admin Role
  }
}

module aksadminaccessRBAC 'modules/Identity/role.bicep' = {
  scope: rg
  name: 'aksadminaccessRBAC'
  params: {
    principalId: aksadminaccessprincipalId
    roleGuid: 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b' //Azure Kubernetes Service RBAC Cluster Admin

  }
}

module keyvaultAccessPolicy 'modules/keyvault/keyvault.bicep' = {
  scope: resourceGroup(keyVaultRGName)
  name: 'akskeyvaultaddonaccesspolicy'
  params: {
    keyvaultManagedIdentityObjectId: aksCluster.outputs.keyvaultaddonIdentity
    vaultName: keyvaultName
  }
}
