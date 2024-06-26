param clusterName string
param logworkspaceid string
param privateDNSZoneId string
param aadGroupdIds array
param subnetId string
param identity object
//param kubernetesVersion string
param location string = resourceGroup().location
param availabilityZones array
param enableAutoScaling bool
param autoScalingProfile object
param podCidr string // = '172.17.0.0/16'
param upgradeChannel string
param nodeOSUpgradeChannel string

param systemNodePoolReplicas int
param userNodePool1Replicas int
param userNodePool2Replicas int

param systemNodePoolSku string
param userNodePool1Sku string
param userNodePool2Sku string
@allowed([
  'Ubuntu'
  'AzureLinux'
])
param osSku string = 'Ubuntu'


@allowed([
  'azure'
  'azure-overlay'
  'kubenet'
])
param networkPlugin string = 'kubenet'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2023-10-01' = {
  name: clusterName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: identity
  }
  properties: {
    //kubernetesVersion: kubernetesVersion
    nodeResourceGroup: '${clusterName}-aksInfraRG'
    dnsPrefix: '${clusterName}aks'
    agentPoolProfiles: [
      {
        enableAutoScaling: enableAutoScaling
        name: 'systempool'
        nodeLabels: {
          role: 'system'
        }        
        availabilityZones: !empty(availabilityZones) ? availabilityZones : null
        mode: 'System'
        enableEncryptionAtHost: true
        count: systemNodePoolReplicas
        nodeTaints: [
          'CriticalAddonsOnly=true:NoSchedule'
        ]
        minCount: enableAutoScaling ? 1 : null
        maxCount: enableAutoScaling ? 3 : null
        vmSize: systemNodePoolSku
        osType: 'Linux'
        osSKU: osSku
        osDiskSizeGB: 30
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: subnetId
      }
      {
        enableAutoScaling: enableAutoScaling
        name: 'usernp1'
        nodeLabels: {
          role: 'usernp1'
        }        
        availabilityZones: !empty(availabilityZones) ? availabilityZones : null
        mode: 'User'
        enableEncryptionAtHost: true
        count: userNodePool1Replicas
        minCount: enableAutoScaling ? 1 : null
        maxCount: enableAutoScaling ? 3 : null
        vmSize: userNodePool1Sku
        osType: 'Linux'
        osSKU: osSku
        osDiskSizeGB: 30
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: subnetId
      }
      {
        enableAutoScaling: enableAutoScaling
        name: 'usernp2'
        nodeLabels: {
          role: 'usernp2'
        }
        availabilityZones: !empty(availabilityZones) ? availabilityZones : null
        mode: 'User'
        enableEncryptionAtHost: true
        count: userNodePool2Replicas
        minCount: enableAutoScaling ? 1 : null
        maxCount: enableAutoScaling ? 3 : null
        vmSize: userNodePool2Sku
        osType: 'Linux'
        osSKU: osSku
        osDiskSizeGB: 30
        type: 'VirtualMachineScaleSets'
        vnetSubnetID: subnetId
      }
    ]
    autoScalerProfile: enableAutoScaling ? autoScalingProfile : null

    autoUpgradeProfile: {
      nodeOSUpgradeChannel: nodeOSUpgradeChannel
      upgradeChannel: upgradeChannel
    }
    
    disableLocalAccounts: true

    // network profile modifications
    // outboundType:
    // https://learn.microsoft.com/en-us/azure/aks/azure-cni-overlay
    //    - loadBalancer
    //    - managedNATGateway
    //    - userAssignedNATGateway
    //    - userDefinedRouting

    networkProfile: networkPlugin == 'azure' ? {
      networkDataplane: 'azure'
      networkPlugin: 'azure'
      outboundType: 'userDefinedRouting'
      dnsServiceIP: '192.168.100.10'
      serviceCidr: '192.168.100.0/24'
      networkPolicy: 'calico'
    } : networkPlugin == 'azure-overlay' ? {
      networkDataplane: 'azure'
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      outboundType: 'userDefinedRouting'
      dnsServiceIP: '192.168.100.10'
      serviceCidr: '192.168.100.0/24'
      podCidr: podCidr
      networkPolicy: 'calico'
    } : {
      networkDataplane: 'azure'
      networkPlugin: 'kubenet'
      outboundType: 'userDefinedRouting'
      dnsServiceIP: '192.168.100.10'
      serviceCidr: '192.168.100.0/24'
      networkPolicy: 'calico'
      podCidr: podCidr
    }

    apiServerAccessProfile: {
      enablePrivateCluster: true
      disableRunCommand: true
      privateDNSZone: privateDNSZoneId
      enablePrivateClusterPublicFQDN: false
    }
    enableRBAC: true
    aadProfile: {
      adminGroupObjectIDs: aadGroupdIds
      enableAzureRBAC: true
      managed: true
      tenantID: subscription().tenantId
    }
    // Required for Workload Identity
    oidcIssuerProfile: {
       enabled: true
    }
    securityProfile: {
      defender: {
        logAnalyticsWorkspaceResourceId: logworkspaceid
        securityMonitoring: {
          enabled: true
        }
      }
      imageCleaner: {
        enabled: true
        intervalHours: 168 // once per week (default)
      }
      workloadIdentity: {
        enabled: true
     }      
    }
    
    addonProfiles: {
      omsagent: {
        config: {
          logAnalyticsWorkspaceResourceID: logworkspaceid
        }
        enabled: true
      }
      azurepolicy: {
        enabled: true
      }
      azureKeyvaultSecretsProvider: {
        enabled: true
      }
    }
  }
}

resource aksdiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'aksdiagnostics'
  scope: aksCluster
  properties: {
    logs: [
      {
        category: 'kube-audit-admin'
        enabled: true
//        retentionPolicy: {
//          days: 30
//          enabled: true
//        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
//        retentionPolicy: {
//          days: 30
//          enabled: true
//        }
      }
    ]
    workspaceId: logworkspaceid
  }
}

output kubeletIdentity string = aksCluster.properties.identityProfile.kubeletidentity.objectId
output keyvaultaddonIdentity string = aksCluster.properties.addonProfiles.azureKeyvaultSecretsProvider.identity.objectId
