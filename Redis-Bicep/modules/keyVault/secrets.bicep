param keyVaultName string

param name string

param value string

resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  name: '${keyVaultName}/${name}'
  properties: {
    value: value
  }
}
