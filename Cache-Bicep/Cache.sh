#!/usr/bin/bash

subscription=00000000-0000-0000-0000-000000000000
vnet=VIRTUAL_NETWORK_NAME
subnet=SUBNET_NAME
location=LOCATION
name=REDIS_NAME
group=RESOURCE_GROUP_NAME
sku=Standard
size=C0
endpoint=REDIS_ENDPOINT_NAME

# Create Redis

az redis create \
--location $location \
--name $name \
--resource-group $group \
--sku $sku \
--vm-size $size

# Create private endpoint

az network private-endpoint create \
--name $endpoint \
--resource-group $group \
--vnet-name $vnet \
--subnet $subnet \
--private-connection-resource-id "/subscriptions/$subscription/resourceGroups/$group/providers/Microsoft.Cache/Redis/$name" \
--group-ids redisCache \
--connection-name $endpoint

# Disable public access to Redis

az redis update \
--name $name \
--resource-group $group \
--set publicNetworkAccess=Disabled

# Create private DNS Zone

az network private-dns zone create \
--name privatelink.redis.cache.windows.net \
--group $group

# Obtain Redis Private Endpoint IP Address

interface=$(az network private-endpoint show \
--name $endpoint --resource-group $group \
--query "networkInterfaces[0].id" \
-o tsv)

ipaddress=$(az network nic show \
--ids $interface \
--query "ipConfigurations[0].privateIPAddress" \
-o tsv)

# Add Redis to Private DNS Zone

az network private-dns record-set a add-record \
--name privatelink.redis.cache.windows.net \
--resource-group $group \
--record-set-name $name \
--ipv4-address $ipaddress
