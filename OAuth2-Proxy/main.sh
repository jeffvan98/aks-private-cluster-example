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
# azure redis cache
# azure key vault with the following secrets: 
#   oauth2-proxy application registration client id
#   oauth2-proxy application registration secret
#   oauth2-proxy redis service name
#   oauth2-proxy redis password
#   oauth2-proxy cookie secret
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

# oauth2-proxy installation namespace; oauth2-proxy may be installed multiple times on a single cluster (per-application); ex: auth-neurology
export AKS_APPLICATION_NAMESPACE=""

# oauth2-proxy ingress base URI; ex: https://dev.contoso.com/
export AKS_APPLICATION_INGRESS_BASE_URI=""

# oauth2-proxy will protect resources located at and below this path; example: neurology
export AKS_APPLICATION_INGRESS_PATH=""

# name of key vault that holds secrets, including redis connectivity; example: VAULT7C02
export KEY_VAULT_NAME=""

# the name of the key vault secret which holds the oauth2-proxy app client id; ex: oauth2-proxy-client-id
export OAUTH2_PROXY_APP_REGISTRATION_CLIENT_ID_KEY=""

# the name of the key vault secret which holds the oauth2-proxy app secret; ex: oauth2-proxy-client-secret
export OAUTH2_PROXY_APP_REGISTRATION_SECRET_KEY=""

# the name of the key vault secret which holds the oauth2-proxy redis server name; ex: oauth2-proxy-redis-name
export OAUTH2_PROXY_REDIS_SERVICE_NAME_KEY=""

# the name of the key vault secret which holds the oauth2-proxy redis server password; ex: oauth2-proxy-redis-password
export OAUTH2_PROXY_REDIS_SERVICE_PASSWORD_KEY=""

# the name of the key vault secret which holds the oauth2-proxy cookie secret; ex: oauth2-proxy-cookie-secret
export OAUTH2_PROXY_COOKIE_SECRET_KEY=""

# ------------------------------------------------------------
# INSTALLATION
# ------------------------------------------------------------

# 1. Prepare for installation (helm, container registry)

echo preparing for installation...

echo logging into container registry...
export CONTAINER_REGISTRY_TOKEN=$(az acr login -n $CONTAINER_REGISTRY_NAME --expose-token --query accessToken -o tsv)
docker login $CONTAINER_REGISTRY_NAME.azurecr.io --username 00000000-0000-0000-0000-000000000000 --password-stdin <<< $CONTAINER_REGISTRY_TOKEN
echo $CONTAINER_REGISTRY_TOKEN | helm registry login $CONTAINER_REGISTRY_NAME.azurecr.io --username 00000000-0000-0000-0000-000000000000 --password-stdin

echo downloading oauth2-proxy template from helm repo...
helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
helm repo update
helm pull oauth2-proxy/oauth2-proxy

echo uploading oauth2-proxy template to container registry...
helm push oauth2-proxy*.tgz oci://$CONTAINER_REGISTRY_NAME.azurecr.io/helm

echo importing container image...
az acr import -n $CONTAINER_REGISTRY_NAME --source quay.io/oauth2-proxy/oauth2-proxy:v7.5.1

echo obtaining redis service name...
export OAUTH2_PROXY_REDIS_SERVICE_NAME=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name $OAUTH2_PROXY_REDIS_SERVICE_NAME_KEY --query value -o tsv)

echo obtaining oauth2-proxy client id...
export OAUTH2_PROXY_CLIENT_ID=$(az keyvault secret show --vault-name $KEY_VAULT_NAME --name $OAUTH2_PROXY_APP_REGISTRATION_CLIENT_ID_KEY --query value -o tsv)

echo obtaining oauth2-proxy application registration redirect uris...
export OAUTH2_PROXY_APP_REGISTRATION_REDIRECT_URIS=$(az ad app show --id $OAUTH2_PROXY_CLIENT_ID --query web.redirectUris -o tsv)

# 2. Install

echo installing oauth2-proxy

echo creating namespace...
kubectl create namespace $AKS_APPLICATION_NAMESPACE

echo creating secret provider class...
export AAD_TENANT_ID=$(az account show --query tenantId -o tsv)
export AKS_SECRET_PROVIDER_ID=$(az aks show -g $AKS_CLUSTER_RESOURCE_GROUP -n $AKS_CLUSTER_NAME --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)
kubectl apply -n $AKS_APPLICATION_NAMESPACE -f - <<EOF
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
   name: oauth2-proxy-spc
spec:
   provider: azure
   parameters:
      usePodIdentity: "false"
      useVMManagedIdentity: "true"
      userAssignedIdentityID: $AKS_SECRET_PROVIDER_ID
      keyvaultName: $KEY_VAULT_NAME
      tenantId: $AAD_TENANT_ID
      objects: |
         array:
            - |
              objectName: $OAUTH2_PROXY_APP_REGISTRATION_CLIENT_ID_KEY
              objectType: secret
            - |
              objectName: $OAUTH2_PROXY_APP_REGISTRATION_SECRET_KEY
              objectType: secret
            - |
              objectName: $OAUTH2_PROXY_REDIS_SERVICE_NAME_KEY
              objectType: secret              
            - |
              objectName: $OAUTH2_PROXY_REDIS_SERVICE_PASSWORD_KEY
              objectType: secret
            - |
              objectName: $OAUTH2_PROXY_COOKIE_SECRET_KEY
              objectType: secret
   secretObjects:
      - secretName: oauth2-proxy-spc-secrets
        type: Opaque
        data:
           - key: client-id
             objectName: $OAUTH2_PROXY_APP_REGISTRATION_CLIENT_ID_KEY
           - key: client-secret
             objectName: $OAUTH2_PROXY_APP_REGISTRATION_SECRET_KEY
           - key: redis-name
             objectName: $OAUTH2_PROXY_REDIS_SERVICE_NAME_KEY            
           - key: redis-password
             objectName: $OAUTH2_PROXY_REDIS_SERVICE_PASSWORD_KEY
           - key: cookie-secret
             objectName: $OAUTH2_PROXY_COOKIE_SECRET_KEY
EOF

echo creating default, empty authorized users config map...
kubectl apply -n $AKS_APPLICATION_NAMESPACE -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
   name: authorized-users
data:
   config-file.txt:
     user@domain.suffix 
EOF

echo installing oauth2-proxy...
cat <<EOF | helm install oauth2-proxy oci://$CONTAINER_REGISTRY_NAME.azurecr.io/helm/oauth2-proxy --namespace=$AKS_APPLICATION_NAMESPACE -f -
config:
   configFile: |-
      azure_tenant = "$AAD_TENANT_ID"
      oidc_issuer_url = "https://login.microsoftonline.com/$AAD_TENANT_ID/v2.0"
      provider = "azure"
      redis_connection_url = "rediss://$OAUTH2_PROXY_REDIS_SERVICE_NAME.redis.cache.windows.net:6380"
      reverse_proxy = "true"
      session_store_type = "redis"
      set_xauthrequest = "true"

image:
   repository: "$CONTAINER_REGISTRY_NAME.azurecr.io/oauth2-proxy/oauth2-proxy"
   tag: "v7.5.1"
   pullPolicy: "IfNotPresent"

replicaCount: 2

authenticatedEmailsFile:
   enabled: "true"
   persistence: "configmap"
   template: "authorized-users"
   restrictedUserAccessKey: "config-file.txt"

nodeSelector:
   role: usernp1

extraVolumes:
   - name: oauth2-proxy-secrets
     csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
           secretProviderClass: oauth2-proxy-spc

extraVolumeMounts:
   - name: oauth2-proxy-secrets
     mountPath: /mnt/secrets-store
     readOnly: true

extraEnv:
   - name: OAUTH2_PROXY_PROXY_PREFIX
     value: /auth/$AKS_APPLICATION_INGRESS_PATH
   - name: OAUTH2_PROXY_CLIENT_ID
     valueFrom:
        secretKeyRef:
           name: oauth2-proxy-spc-secrets
           key: client-id
   - name: OAUTH2_PROXY_CLIENT_SECRET
     valueFrom:
        secretKeyRef:
           name: oauth2-proxy-spc-secrets
           key: client-secret
   - name: OAUTH2_PROXY_COOKIE_SECRET
     valueFrom:
        secretKeyRef:
           name: oauth2-proxy-spc-secrets
           key: cookie-secret
   - name: OAUTH2_PROXY_REDIS_PASSWORD
     valueFrom:
        secretKeyRef:
           name: oauth2-proxy-spc-secrets
           key: redis-password

ingress:
   enabled: false
EOF

echo creating authentication ingress...
kubectl apply -n $AKS_APPLICATION_NAMESPACE -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
   name: oauth2-proxy
   annotations:
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
   ingressClassName: nginx
   rules:
   - http:
      paths:
      - path: /auth/$AKS_APPLICATION_INGRESS_PATH
        pathType: Prefix
        backend:
           service:
              name: oauth2-proxy
              port:
                number: 80
EOF

echo registering authentication ingress with app registration...
az ad app update --id $OAUTH2_PROXY_CLIENT_ID --web-redirect-uris $OAUTH2_PROXY_APP_REGISTRATION_REDIRECT_URIS $AKS_APPLICATION_INGRESS_BASE_URI/auth/$AKS_APPLICATION_INGRESS_PATH

echo done.