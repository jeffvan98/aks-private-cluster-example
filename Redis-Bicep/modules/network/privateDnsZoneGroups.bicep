param privateEndpointName string

param privateDnsZoneId string

resource privateDnZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {  
  name: '${privateEndpointName}/group01'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'config1'
      properties: {
        privateDnsZoneId: privateDnsZoneId
      }
    }]
  }
}
