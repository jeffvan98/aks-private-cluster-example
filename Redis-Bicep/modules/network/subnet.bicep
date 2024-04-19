param virtualNetworkName string

param subnetName string

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: virtualNetworkName
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: virtualNetwork
  name: subnetName
}

output subnetId string = subnet.id
output subnetName string = subnet.name
