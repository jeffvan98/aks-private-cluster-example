targetScope = 'subscription'

// ------------------------------------------------------------
// This template will create an instance of redis.
// It will connect this instance of redis to the specified virtual network and subnet.
// It will create a private DNS zone and connect it to the specified virtual network for redis.
// It will store redis connection information in the specified key vault.
// ------------------------------------------------------------


// ------------------------------------------------------------
// Parameters
// ------------------------------------------------------------

// redis service resource group
param redisResourceGroupName string

// redis service name
param redisName string

// redis service sku
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param redisSku string

// redis service family
@allowed([
  'C'
  'P'
])
param redisFamily string

// redis service capacity
@allowed([
  0
  1
  2
  3
  4
  5
  6
])
param redisCapacity int

// redis will be connected to a virtual network; specify its resource group
param redisVirtualNetworkResourceGroupName string

// redis will be connected to this virtual network
param redisVirtualNetworkName string

// redis will be connected to this subnet from the virtual network
param redisSubnetName string

// a private dns zone will be created; specify the desired resource group for this dns zone
param privateDnsZoneResourceGroupName string

// specify the resource group of the virtual network that the private DNS zone will connect to
param privateDnsZoneVirtualNetworkResourceGroupName string

// specify the name of the virtual network that the private DNS zone will connect to
param privateDnsZoneVirtualNetworkName string

// redis connectivity information will be stored in keyvault; specify the keyvault's resource group
param keyVaultResourceGroupName string

// specify the name of the keyvault
param keyVaultName string

// specify the redis service host name key; this key will hold the redis service name in keyvault
param redisHostNameKey string

// specify the redis service access key name; this name will hold the redis service key in keyvault
param redisAccessKey string

param currentDateTime string = utcNow()

// ------------------------------------------------------------
// Existing resources
// ------------------------------------------------------------

resource redisResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: redisResourceGroupName
}

resource redisVirtualNetworkResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: redisVirtualNetworkResourceGroupName
}

resource privateDnsZoneResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: privateDnsZoneResourceGroupName
}

resource privateDnsZoneVirtualNetworkResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: privateDnsZoneVirtualNetworkResourceGroupName
}

resource keyVaultResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' existing = {
  name: keyVaultResourceGroupName
}

// ------------------------------------------------------------
// Deployment
// ------------------------------------------------------------

module redis 'modules/redis/redis.bicep' = {
  scope: redisResourceGroup
  name: 'redis-${currentDateTime}'
  params: {
    location: redisResourceGroup.location
    name: redisName
    sku: redisSku
    family: redisFamily
    capacity: redisCapacity
  }
}

module redisVirtualNetwork 'modules/network/virtualNetwork.bicep' = {
  scope: redisVirtualNetworkResourceGroup
  name: 'redisVirtualNetwork-${currentDateTime}'
  params: {
    virtualNetworkName: redisVirtualNetworkName    
  }
}

module privateDnsZoneVirtualNetwork 'modules/network/virtualNetwork.bicep' = {
  scope: privateDnsZoneVirtualNetworkResourceGroup
  name: 'privateDnsZoneVirtualNetwork-${currentDateTime}'
  params: {
    virtualNetworkName: privateDnsZoneVirtualNetworkName
  }
}

module redisSubnet 'modules/network/subnet.bicep' = {
  scope: redisVirtualNetworkResourceGroup
  name: 'redisSubnet-${currentDateTime}'
  params: {
    virtualNetworkName: redisVirtualNetwork.outputs.virtualNetworkName
    subnetName: redisSubnetName
  }
}

module redisPrivateEndpoint 'modules/network/privateEndpoints.bicep' = {
  scope: redisResourceGroup
  name: 'redisPrivateEndpoint-${currentDateTime}'
  params: {
    location: redisResourceGroup.location
    name: '${redisName}-endpoint'
    subnet: redisSubnet.outputs.subnetId
    service: redis.outputs.redisId
    group: 'redisCache'
  }
}

module privateDnsZone 'modules/network/privateDnsZones.bicep' = {
  scope: privateDnsZoneResourceGroup
  name: 'privateDnsZone-${currentDateTime}'
  params: {   
    name: 'privatelink.redis.cache.windows.net' 
  }
}

module privateDnsZoneGroups 'modules/network/privateDnsZoneGroups.bicep' = {
  scope: redisResourceGroup
  name: 'redisResourceGrou-${currentDateTime}'
  params: {
    privateEndpointName: redisPrivateEndpoint.outputs.privateEndpointName
    privateDnsZoneId: privateDnsZone.outputs.privateDnsZoneId
  }
}

module virtualNetworkLink 'modules/network/virtualNetworkLinks.bicep' = {
  scope: privateDnsZoneResourceGroup
  name: 'virtualNetworkLink-${currentDateTime}'
  params: {
    name: '${redisVirtualNetwork.outputs.virtualNetworkName}-link'
    privateDnsZoneName: privateDnsZone.outputs.privateDnsZoneName
    virtualNetworkId: privateDnsZoneVirtualNetwork.outputs.virtualNetworkId
  }
}

module redisHostNameSecret 'modules/keyVault/secrets.bicep' = {
  scope: keyVaultResourceGroup
  name: 'redisHostNameSecret-${currentDateTime}'
  params: {
    keyVaultName: keyVaultName
    name: redisHostNameKey
    value: redis.outputs.redisName
  }
}

module redisKeySecret 'modules/keyVault/secrets.bicep' = {
  scope: keyVaultResourceGroup
  name: 'redisKeySecret-${currentDateTime}'
  params: {
    keyVaultName: keyVaultName
    name: redisAccessKey
    value: redis.outputs.redisAccessKey
  }
}
