param virtualNetworkName string

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: virtualNetworkName
}

output virtualNetworkId string = virtualNetwork.id
output virtualNetworkName string = virtualNetwork.name

