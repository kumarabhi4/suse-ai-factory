#!/bin/bash

RKE2_VERSION="v1.33.12+rke2r1"

mkdir -p /etc/rancher/rke2
cat <<EOF> /etc/rancher/rke2/config.yaml
use-service-account-credentials: true
token: "rantoken"
tls-san:
  - "master2.dnt.adc.delllabs.net"
  - "hclaif.delllabs.net"
  - "rancher.hclaif.delllabs.net"
  - "100.67.174.14"
EOF
chmod 640 /etc/rancher/rke2/config.yaml
curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION=${RKE2_VERSION} sh -
systemctl enable rke2-server
systemctl start rke2-server

RANCHERVERSION="v2.14.5"
#RANCHERNAME=$(hostname --fqdn)
RANCHERNAME=master2.dnt.adc.delllabs.net
BOOTSTRAPADMINPWD="hclaif!"
RANCHERADMINPWD="hclaif"

#kubectl create namespace cattle-system
helm repo add jetstack https://charts.jetstack.io
helm repo add rancher-prime https://charts.rancher.com/server-charts/prime

helm repo update
echo "\_helm install cert-manager jetstack/cert-manager .."
helm install cert-manager jetstack/cert-manager  --namespace cert-manager --create-namespace --set crds.enabled=true

echo "\_waiting for cert-manager deployment rollout status.."
kubectl -n cert-manager rollout status deploy/cert-manager

echo "\_sleeping for 1 minute.."
sleep 60

# issuer
cat << EOF >./selfsigned-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
---
EOF

kubectl apply -f ./selfsigned-issuer.yaml
kubectl wait --for=condition=Ready clusterissuer --all --timeout=300s



echo "\_helm install rancher (version=${RANCHERVERSION}).."

helm install rancher rancher-prime/rancher \
    --namespace cattle-system --create-namespace \
    --version=${RANCHERVERSION} \
    --set hostname=${RANCHERNAME} \
    --set replicas=1 \
    --set bootstrapPassword=${BOOTSTRAPADMINPWD} \
    --set noDefaultAdmin=false \
    --set agentTLSMode=system-store

kubectl -n cattle-system rollout status deploy/rancher


# rancher config - cli here, can ben done in UI
# override min password length
cat <<EOF | kubectl apply -f -  
apiVersion: management.cattle.io/v3
kind: Setting
metadata:
  name: password-min-length
  namespace: cattle-system
value: "6"
EOF

# change admin password
echo "\__Setting Admin Password.."
token=$(curl -sk "https://$RANCHERNAME/v3-public/localProviders/local?action=login" \
    -X POST \
    -H 'content-type: application/json' \
    -d "{\"username\":\"admin\",\"password\":\"$BOOTSTRAPADMINPWD\"}" | jq -r .token \
  )
api_token=$(curl -sk "https://$RANCHERNAME/v3/token" \
    -X POST \
    -H 'content-type: application/json' \
    -H "Authorization: Bearer $token" \
    -d '{"type":"token","description":"automation"}' | jq -r .token \
  )
# set admin password
curl -sk "https://$RANCHERNAME/v3/users?action=changepassword" \
    -X POST \
    -H 'content-type: application/json' \
    -H "Authorization: Bearer $api_token" \
    -d "{\"currentPassword\":\"$BOOTSTRAPADMINPWD\",\"newPassword\":\"$RANCHERADMINPWD\"}"


# set rancher server url (needed so rancher cluster import cli creates registration urls)
  Log "\__Setting Rancher URL.."
  curl -sk "https://$RANCHERNAME/v3/settings/server-url" \
    -X PUT \
    -H 'content-type: application/json' \
    -H "Authorization: Bearer $api_token" \
    -d "{\"name\":\"server-url\",\"value\":\"https://$RANCHERNAME\"}"


# add rancher extension repositories
# Rancher Extensions repo
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: rancher-ui-plugins
  annotations:
    field.cattle.io/description: Rancher UI Plugins
spec:
  gitRepo: https://github.com/rancher/ui-plugin-charts
  gitBranch: main
EOF
# Partner Extensions repo
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: partner-extensions
  annotations:
    field.cattle.io/description: Partner UI Extensions
spec:
  gitRepo: https://github.com/rancher/partner-extensions
  gitBranch: main
EOF
