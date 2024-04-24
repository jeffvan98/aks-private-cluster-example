# Overview

This solution contains two sets of Bicep templates and two shell scripts.
1. The first template deploys a secure AKS baseline cluster.
2. The second template deploys a secure instance of Redis. Redis is intended to be used with the AKS cluster.
3. The first shell script deploys ingress-nginx ingress controller.  This is to be run once.
4. The second shell script deploys oauth2-proxy.  This is to be run once per security domain (applicaition) on the cluster

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

# Ingress-Nginx

## Description

This script installs Ingress-Nginx, available from https://kubernetes.github.io/ingress-nginx.

The script assumes that you are working with a private AKS cluster and supporting services, like Azure Container Registry.

The script first attempts to pull the ingress-nginx and supporting container images into yoour private container registry. 

Then, the script installs Ingress-Nginx using the ingress-nginx helm chart.

Ingress-nginx is installed into a user specifieid kubernetes namespace.  Traffic to/from the ingress controller is secured using TLS and a user-specified digital certificate that is to come from Azure Key Vault.

### Prep

This script requires several command line tools in order to run.  These include: the Azure CLI, the Kubernetes CLI, the Docker CLI, and the Helm CLI.

This script interacts with your Azure Kubernetes Service, Azure Container Registry, and Azure Key Vault.

A number of parameters that are specific to your environment must be entered into the script before running.

### Deploy

# OAuth2-Proxy

## Description

This script install OAuth2-Proxy, available from https://oauth2-proxy.github.io/manifests.

The script is designed to install OAuth2-Proxy multiple times on an AKS cluster.  This is because each instance of OAuth2-Proxy is to be used for a specific security boundary - a boundary that is controlled using kubernetes config-maps (lists of authorized users).  This is an intentional decision that is based on a specific usecase requirement.

This script assumes that you are working with a private AKS cluster, and supporting services, like Azure Container Registry, Azure Key Vault, and Azure Redis Cache.

Like the Ingress-Nginx script, this script first attempts to pull the OAuth2-Proxy and supporting container image into your private container registry.

Then, the script installs OAuth2-Proxy using the OAuth2-Proxy helm chart.

OAuth2-Proxy is installed into a user specified kuberentes namespace. This namespace and the objects it includes should be reserved for OAuth2-Proxy.

OAuth2-Proxy configuration requires a number of parameters, including the base URI for the application (https://app.domain.com), the ingress path for authenticating users (test-app), the name of an Azure Key Vault with various supporting secrets, including: the Azure AD/Entra Application ID for OAuth2 Proxy, a secret for this app, the name of your Azure Redis cache, the password for Azure Redis cache, and a user-generated OAuth2-Proxy cookie secret.

### Prep

This script requires several command line tools in order to run.  These include: the Azure CLI, the Kubernetes CLI, the Docker CLI, and the Helm CLI.

This script makes updates to the OAuth2 Proxy Azure AD/Entra Application (redirect URIs).

A number of parameters that are specific to your environment must be entered into the script before running.

### Deploy

Edit and populate the parameters of Ingress-Nginx/main.sh. Then, run it.
