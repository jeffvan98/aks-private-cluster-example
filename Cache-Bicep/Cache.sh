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

az redis create \
--location $location \
--name $name \
--resource-group $group \
--sku $sku \
--vm-size $size

az network private-endpoint create \
--name $endpoint \
--resource-group $group \
--vnet-name $vnet \
--subnet $subnet \
--private-connection-resource-id "/subscriptions/$subscription/resourceGroups/$group/providers/Microsoft.Cache/Redis/$name" \
--group-ids redisCache \
--connection-name $endpoint

az redis update \
--name $name \
--resource-group $group \
--set publicNetworkAccess=Disabled