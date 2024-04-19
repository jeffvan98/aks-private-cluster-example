# Overview

This solution contains two sets of Bicep templates.
1. The first template deploys a secure AKS baseline cluster.
2. The second template deploys a secure instance of Redis. Redis is intended to be used with the AKS cluster.

# Secure AKS Template

## Deploy Template

This template deploys a secure AKS baseline cluster with the following high-level setup: 
- 3 node pools (2 user node pools, 1 system node pool)
- Security and Private networking features enabled
- Expects existing vnet, route table, keyvault, and log analytics workspace which can exist in separate resource groups than the deployed AKS cluster.

### Prep:
- Create a resource group to be used, if there is not already one created
- Create AAD groups for Devs and Admins cluster access, these will be used as PrincipalID paramteres in the template.
- Enable host encryption feature:
  `az feature register --namespace  Microsoft.Compute --name EncryptionAtHost`
- Once registration is complete, run: `az provider register -n Microsoft.Compute`
- Requires existing vnet/subnet with udr set on subnet

### Deploy
1. Update parameters-dev.json template for Dev deployment, as an example
2. Deploy Template, update location to match desired cluster region:

**Dev Deployment:**
```
az deployment sub create --template-file AKS-Cluster-Bicep/main.bicep --parameters @AKS-Cluster-Bicep/parameters-dev.json --location eastus2
```
**Prod Deployment:**
```dotnetcli
az deployment sub create --template-file AKS-Cluster-Bicep/main.bicep --parameters @AKS-Cluster-Bicep/parameters-prod.json --location westus3
```

# Secure Redis Template

## Deploy Template
This template deploys a secure Redis cache with the following high-level setup:
- Open Source Azure redis service
- Secure network connectivity; insecure communication disabled; public connectivity disabled; private networking with private endpoint enabled
- Expects:
   - Existing resource group to receive redis
   - Existing virtual network and subnet to receive redis private endpoint
   - Existing virtual network to receive redis private DNS zone (may be the same as above)
   - Existing key vault to receive redis connectivity information

### Prep
- Update/create parameters json file using parameters-dev.json as a template

### Deploy
1. Run the following command with a parameters file for your environment and the desired location (ex: eastus)
```dotnetcli
az deployment sub create --template-file Redis-Bicep/main.bicep --parameters @<PARAMETER-FILE-NAME> --location <LOCATION>
```

