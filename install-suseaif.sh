#!/bin/bash

# SUSE Application Collection - service account values
APPCOL_USER=
APPCOL_TOKEN=

# SUSE AI Subscription key
SUSE_AI_SUB=

echo set vars first
exit


# add application-collection repo
# secret
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: clusterrepo-auth-suseappcol
  namespace: cattle-system
type: kubernetes.io/basic-auth
stringData:
  username: $APPCOL_USER
  password: $APPCOL_TOKEN
EOF

# clusterrepo
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: application-collection
  annotations:
    field.cattle.io/description: SUSE Application Collection
spec:
  clientSecret:
    name: clusterrepo-auth-suseappcol
    namespace: cattle-system
  insecurePlainHttp: false
  url: oci://dp.apps.rancher.io/charts
EOF

# add suse-ai-registry repo
# secret
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: clusterrepo-auth-suseaireg
  namespace: cattle-system
type: kubernetes.io/basic-auth
stringData:
  username: regcode
  password: $SUSE_AI_SUB
EOF

# clusterrepo
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: suse-ai-registry
  annotations:
    field.cattle.io/description: SUSE AI Registry
spec:
  clientSecret:
    name: clusterrepo-auth-suseaireg
    namespace: cattle-system
  insecurePlainHttp: false
  url: oci://registry.suse.com/ai/charts
EOF

# https://documentation.suse.com/suse-ai-factory/latest/html/AI-Factory-deployment/aif-deployment-prepare.html

# gpu-operator
# https://documentation.suse.com/cloudnative/rke2/latest/en/add-ons/gpu_operators.html
helm search repo nvidia --versions | grep gpu-operator | head -1

# https://documentation.suse.com/suse-ai-factory/latest/html/AI-Factory-deployment/aif-deployment.html#ai-factory-deployment-helm
# https://documentation.suse.com/suse-ai-factory/latest/html/AI-Factory-deployment/aif-deployment.html#aif-helm-credentials-procedure

