param location string = resourceGroup().location

var policyDefinitionIdValue = '/providers/Microsoft.Authorization/policyDefinitions/64def556-fbad-4622-930e-72d1d5589bf5'

resource DefAKSAssignment 'Microsoft.Authorization/policyAssignments@2021-06-01' = {
    name: 'EnableDefenderForAKS'
    location: location
    properties: {
      #disable-next-line use-resource-id-functions
      policyDefinitionId: policyDefinitionIdValue
    }
    identity: {
      type: 'SystemAssigned'
    }
}
