#!/bin/bash

helm repo add longhorn https://charts.longhorn.io
helm repo update

# fdisk - prepare volume partition
mkfs.xfs /dev/nvme1n1p1
mkdir -p /var/lib/longhorn
echo "/dev/nvme1n1p1 /var/lib/longhorn xfs noatime 0 0" >> /etc/fstab
mount /var/lib/longhorn


echo " \_Creating longhorn helm chart values.."
cat << LEOF >./longhorn-values.yaml
defaultSettings:
  defaultReplicaCount: 1
persistence:
  defaultClass: true
  defaultFsType: xfs
  defaultClassReplicaCount: 1
LEOF

echo " \_Installing longhorn helm chart.."
helm upgrade \
    --install longhorn longhorn/longhorn \
    --namespace longhorn-system \
    --create-namespace \
    -f ./longhorn-values.yaml \
    --timeout=5m

echo " \_Waiting for longhorn chart rollout.."
 kubectl wait pods -n longhorn-system \
    -l app.kubernetes.io/instance=longhorn --for condition=Ready \
    --timeout=300s
