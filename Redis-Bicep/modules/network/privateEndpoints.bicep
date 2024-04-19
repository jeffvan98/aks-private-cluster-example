param location string = resourceGroup().location

param name string

param subnet string

param service string

param group string

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  location: location
  name: name
  properties: {
    subnet: {
      id: subnet  
    }
    customNetworkInterfaceName: '${name}-nic'
    privateLinkServiceConnections: [{
      name: '${name}-connection'
      properties:{
        privateLinkServiceId: service
        groupIds: [ group ]
      }
    }      
    ]
  }  
}

output privateEndpointId string = privateEndpoint.id
output privateEndpointName string = privateEndpoint.name
