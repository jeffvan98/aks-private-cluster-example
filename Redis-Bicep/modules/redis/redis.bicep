param location string = resourceGroup().location

param name string

@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param sku string

@allowed([
  'C'
  'P'
])
param family string

@allowed([
  0
  1
  2
  3
  4
  5
  6
])
param capacity int

resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  location: location
  name: name
  properties: {
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    sku: {
      name: sku
      family: family
      capacity: capacity
    }
  }
}

var accessKey = redis.listKeys().primaryKey

output redisId string = redis.id
output redisName string = redis.name
output redisAccessKey string = accessKey
