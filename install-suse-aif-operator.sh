#!/bin/bash

source ./params.sh

clusterrepo-auth-suseaireg


# clusterrepo
cat <<EOF | kubectl --kubeconfig=./local/rancher-admin.conf apply -f -  > /dev/null 2>&1
apiVersion: catalog.cattle.io/v1
kind: ClusterRepo
metadata:
  name: suse-aif-operator
  annotations:
    field.cattle.io/description: SUSE AIF Registry
spec:
  clientSecret:
    name: clusterrepo-auth-suseaireg
    namespace: cattle-system
  insecurePlainHttp: false
  url: oci://ghcr.io/suse/chart/aif-operator
EOF

# install operator
helm install aif-operator \
  oci://ghcr.io/suse/chart/aif-operator:${SUSE_AIF_OPERATOR_VERSION} \
  --namespace aif-operator --create-namespace


# application collection and suse ai registry secrets in aif-operator namespace for UI entry
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: clusterrepo-auth-suseappcol
  namespace: aif-operator
type: kubernetes.io/basic-auth
stringData:
  username: $APPCOL_USER
  password: $APPCOL_TOKEN
EOF
# secret
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: clusterrepo-auth-suseaireg
  namespace: aif-operator
type: kubernetes.io/basic-auth
stringData:
  username: regcode
  password: $SUSE_AI_SUB
EOF
# secret - nvidia
cat <<EOF | kubectl apply -f -  > /dev/null 2>&1
apiVersion: v1
kind: Secret
metadata:
  name: clusterrepo-auth-nvidiareg
  namespace: aif-operator
type: kubernetes.io/basic-auth
stringData:
  username: "\$oauthtoken"
  password: $SUSE_AIF_NVIDIA_API_KEY
EOF

# note: could create the namespace and secrets first and install operator with a helm values file for the credentails
