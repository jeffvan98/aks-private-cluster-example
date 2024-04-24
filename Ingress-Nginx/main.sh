#!/bin/bash

# ------------------------------------------------------------
# REQUIREMENTS
#
# tools:
# azure cli (az)
# kubernetes cli (kubectl)
# docker cli (docker)
# helm cli (helm)
#
# environment:
# azure kubernetes service
# azure container registry
# azure key vault with desired TLS certificate
#
# parameters:
# populate parameters according to your needs
# 
# ------------------------------------------------------------

# ------------------------------------------------------------
# PARAMETERS
# ------------------------------------------------------------

# container registry name; example: ACR7C02
export CONTAINER_REGISTRY_NAME=""

# cluster name; example: AKS7C02
export AKS_CLUSTER_NAME=""

# cluster resource group; example: 2024-04-22-RG-01
export AKS_CLUSTER_RESOURCE_GROUP=""

# ingress controller kuberentes namespace; this namespace will be created; example: ingress-nginx
export AKS_INGRESS_NAMESPACE=""

# name of ceritificate that will be used with the ingress controller (TLS); example: 
export AKS_INGRESS_CERTIFICATE_NAME=""

# ip address of ingress controller; example: 10.8.2.250
export AKS_INGRESS_IP_ADDRESS=""

# name of key vault that holds the certificate; example: VAULT7C02
export KEY_VAULT_NAME=""

# ------------------------------------------------------------
# INSTALLATION
# ------------------------------------------------------------

# 1. Prepare for installation (helm, container registry)

echo preparing for installation...

echo logging into container registry...
export CONTAINER_REGISTRY_TOKEN=$(az acr login -n $CONTAINER_REGISTRY_NAME --expose-token --query accessToken -o tsv)
docker login $CONTAINER_REGISTRY_NAME.azurecr.io --username 00000000-0000-0000-0000-000000000000 --password-stdin <<< $CONTAINER_REGISTRY_TOKEN
echo $CONTAINER_REGISTRY_TOKEN | helm registry login $CONTAINER_REGISTRY_NAME.azurecr.io --username 00000000-0000-0000-0000-000000000000 --password-stdin

echo downloading ingress-nginx template from helm repo...
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm pull ingress-nginx/ingress-nginx

echo uploading ingress-nginx template to container registry...
helm push ingress-nginx*.tgz oci://$CONTAINER_REGISTRY_NAME.azurecr.io/helm

echo importing container images...
az acr import -n $CONTAINER_REGISTRY_NAME --source registry.k8s.io/ingress-nginx/controller:v1.9.4
az acr import -n $CONTAINER_REGISTRY_NAME --source registry.k8s.io/ingress-nginx/kube-webhook-certgen:v20231011-8b53cabe0
az acr import -n $CONTAINER_REGISTRY_NAME --source registry.k8s.io/defaultbackend-amd64:1.5

# 2. Install

echo installing ingress controller

echo creating namespace...
kubectl create namespace $AKS_INGRESS_NAMESPACE

echo creating secret provider class...
export AAD_TENANT_ID=$(az account show --query tenantId -o tsv)
export AKS_SECRET_PROVIDER_ID=$(az aks show -g $AKS_CLUSTER_RESOURCE_GROUP -n $AKS_CLUSTER_NAME --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)
kubectl apply -f - <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
   name: azure-tls
   namespace:  $AKS_INGRESS_NAMESPACE
spec:
   provider: azure
   secretObjects:
      - secretName: ingress-tls-csi
        type: kubernetes.io/tls
        data:
           - objectName: $AKS_INGRESS_CERTIFICATE_NAME
             key: tls.key
           - objectName: $AKS_INGRESS_CERTIFICATE_NAME
             key: tls.crt
   parameters:
      usePodIdentity: "false"
      useVMManagedIdentity: "true"
      userAssignedIdentityID: $AKS_SECRET_PROVIDER_ID 
      keyvaultName: $KEY_VAULT_NAME
      objects:  |
         array:
            - |
              objectName: $AKS_INGRESS_CERTIFICATE_NAME
              objectType: secret
      tenantId: $AAD_TENANT_ID
EOF

echo installing ingress controller...
helm install ingress-nginx oci://$CONTAINER_REGISTRY_NAME.azurecr.io/helm/ingress-nginx \
-n $AKS_INGRESS_NAMESPACE \
-f - <<EOF
controller:
   image:
      registry: $CONTAINER_REGISTRY_NAME.azurecr.io
      image: ingress-nginx/controller
      tag: v1.9.4
      digest: ""
   nodeSelector:
      role: usernp1
   replicaCount: 2
   service:
      annotations:
         service.beta.kubernetes.io/azure-load-balancer-health-probe-request-path: /healthz
         service.beta.kubernetes.io/azure-load-balancer-internal: true
      loadBalancerIP: $AKS_INGRESS_IP_ADDRESS
   admissionWebhooks:
      patch:
         image:
            registry: $CONTAINER_REGISTRY_NAME.azurecr.io
            image: ingress-nginx/kube-webhook-certgen
            tag: v20231011-8b53cabe0
            digest: ""
         nodeSelector:
            role: usernp1
   config:
      allow-snippet-annotations: true
   extraArgs:
      default-ssl-certificate: ingress-nginx/ingress-tls-csi
   extraVolumes:
   - name: secrets-store-inline
     csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
           secretProviderClass: azure-tls
   extraVolumeMounts:
   - name: secrets-store-inline
     mountPath: "/mnt/secrets-store"
     readOnly: true
defaultBackend:
   enabled: true
   image:
      registry: $CONTAINER_REGISTRY_NAME.azurecr.io
      image: defaultbackend-amd64
      tag: 1.5
      digest: ""
EOF

echo done!

echo ...
echo ...
echo ...

echo useful verification tools:
echo 1. verify secret provider class
echo    kubectl get secretproviderclass -n $AKS_INGRESS_NAMESPACE
echo 2. verify secret
echo    kubectl get secret -n $AKS_INGRESS_NAMESPACE
echo 3. verify secret contents
echo    kubectl describe secret ingress-tls-csi -n $AKS_INGRESS_NAMESPACE
echo 4. verify pods
echo    kubectl get pod -n $AKS_INGRESS_NAMESPACE
echo 5. verify ingress
echo    curl -k -v --resolve YOUR-INGRESS.DOMAIN.COM:443:$AKS_INGRESS_IP_ADDRESS https://YOUR-INGRESS.DOMAIN.COM

