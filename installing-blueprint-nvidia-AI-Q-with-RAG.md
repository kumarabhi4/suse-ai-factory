# Comprehensive Deployment and Troubleshooting Guide: NVIDIA AI-Q Blueprint on Kubernetes

This document consolidates and organizes the deployment prerequisites, hardware configuration (Time-Slicing vs. MIG), cluster tuning, and resolution of common errors encountered when standing up the **NVIDIA AI-Q** (with RAG) blueprint.

---

## 1. Overview of Key Technologies

* **NVIDIA AI-Q (*"IQ"*)**: An open-source reference architecture and multi-agent blueprint for autonomous enterprise deep research. It orchestrates pipelines using shallow paths (instant answers/citations) or deep paths (parallel multi-agent research, sandboxed code execution, and synthesis).
* **NVIDIA NIM (Inference Microservice)**: Containerized microservices bundling hardware-optimized inference engines (TensorRT, TensorRT-LLM, Triton Server) with standard OpenAI-compliant REST/gRPC endpoints.
* **GPU Partitioning Models**:
  * **Time-Slicing**: Software-level oversubscription sharing GPU memory and compute across multiple replicas via time-multiplexing.
  * **MIG (Multi-Instance GPU)**: Hardware-level silicon isolation (on A100, H100, H200, B200) guaranteeing dedicated VRAM, memory bandwidth, and compute failure domains.

---

## 2. Cluster Prerequisites & Pre-Flight Checklist

### 2.1 Pod Density Adjustment (RKE2 Cluster Tuning)
When scaling worker nodes to support high pod densities (e.g., from 110 to 250 pods):

1. **Adjust the Subnet Mask on Server Nodes (`/etc/rancher/rke2/config.yaml`)**:
   ```yaml
   kube-controller-manager-arg:
     - "node-cidr-mask-size=23"

```

Restart the server: `sudo systemctl restart rke2-server`.
2. **Configure Node Kubelet Limits (`/etc/rancher/rke2/config.yaml`)**:

```yaml
kubelet-arg:
  - "max-pods=250"

```

Restart the agent/server: `sudo systemctl restart rke2-agent`.
3. **Tune Host System Limits (`/etc/sysctl.d/99-kubernetes.conf`)**:

```ini
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
fs.file-max = 2097152


Apply with: `sudo sysctl --system`.

---

### 2.2 NGC Credentials Configuration

1. Sign in to the **NVIDIA NGC Portal** with your Enterprise tenant (NVAIE).
2. Generate an API Key from **Profile > Setup > Generate API Key**.
3. Create the image pull secret in your AI-Q namespace:
```bash
kubectl create secret docker-registry ngc-secret \
  --docker-server=nvcr.io \
  --docker-username='$oauthtoken' \
  --docker-password='<YOUR_NGC_API_KEY>' \
  -n ns-aiq

```



---

### 2.3 AI-Q Blueprint Prerequisites & Namespace Setup

Before deploying the blueprint, configure the mandatory namespace, secrets, and configuration maps:

1. **Verify Required Operators**:
* **NVIDIA k8s-nim-operator**
* **Elastic Cloud on Kubernetes (ECK) Operator**


2. **Create Namespace and Secret**:
```bash
kubectl create namespace ns-aiq

kubectl create secret generic aiq-credentials -n ns-aiq \
  --from-literal=NVIDIA_API_KEY="<YOUR_NGC_API_KEY>" \
  --from-literal=TAVILY_API_KEY="<OPTIONAL_TAVILY_KEY>" \
  --from-literal=DB_USER_NAME="aiq" \
  --from-literal=DB_USER_PASSWORD="aiq_dev"

```


3. **Fetch & Apply Web Fragment ConfigMap**:
```bash
curl -fsSL [https://raw.githubusercontent.com/SUSE/aif/main/examples/config_web_frag_2_1_0_updated.yaml](https://raw.githubusercontent.com/SUSE/aif/main/examples/config_web_frag_2_1_0_updated.yaml) \
  -o config_web_frag_2_1_0_updated.yaml

kubectl create configmap aiq-web-frag-config -n ns-aiq \
  --from-file=config_web_frag.yml=config_web_frag_2_1_0_updated.yaml

```



---

## 3. GPU Partitioning Strategy: 4x H100 NVL (94 GB Each)

The full reference architecture expects 8 full GPUs. When operating on 4 cards, hardware or software partitioning is required.

### Note on MIG Geometry on H100 NVL

H100 NVL GPUs contain 7 compute slices. Because 7 cannot be divided equally by 3, **you cannot create 3 equal hardware MIG partitions (e.g., 3 x 32 GB)**.

* **Option A: Hardware MIG**: Unequal partitioning such as $1 \times \text{`3g.47gb`} + 1 \times \text{`2g.24gb`} + 2 \times \text{`1g.12gb`}$, or symmetric $3 \times \text{`2g.24gb`}$ leaving 1 slice unused.
* **Option B: Time-Slicing (Recommended for 12 Identical Virtual Units)**: Carves 3 virtual replicas per GPU across all 4 cards, advertising 12 standard `nvidia.com/gpu` units.

---

### Configuring Time-Slicing for 12 Replicas

1. **Define the Time-Slicing ConfigMap**:
```yaml
# time-slicing-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: time-slicing-config
  namespace: gpu-operator
data:
  h100-3x: |-
    version: v1
    sharing:
      timeSlicing:
        renameByDefault: false
        failRequestsGreaterThanOne: false
        resources:
          - name: [nvidia.com/gpu](https://nvidia.com/gpu)
            replicas: 3

```


Apply: `kubectl apply -f time-slicing-config.yaml`.
2. **Patch the ClusterPolicy**:
```bash
kubectl patch clusterpolicy cluster-policy \
  --type='json' \
  -p='[
    {"op": "replace", "path": "/spec/mig/strategy", "value": "none"},
    {"op": "replace", "path": "/spec/devicePlugin/config", "value": {"name": "time-slicing-config", "default": "h100-3x"}}
  ]'

```


3. **Verify Node Allocation**:
```bash
kubectl get nodes -o custom-columns=NAME:.metadata.name,GPUS:.status.allocatable.'nvidia\.com/gpu'

```


*Expected output: 12 GPUs allocatable on the 4-card node.*

---

## 4. Troubleshooting Encountered Deployment Errors

### 4.1 MIG Manager Fails with `ERROR_IN_USE` / `exit status 1`

* **Root Cause 1: Active CUDA Processes**: Processes like `tritonserver` or `nvidia-persistenced` hold open handles on `/dev/nvidia*`. Slicing requires zero open file handles.
* **Root Cause 2: Slice Alignment / Collision**: Hardware placement order failed due to overlapping indices.

**Resolution Steps**:

1. Stop running workloads and host persistence services:
```bash
kubectl drain <node-name> --delete-emptydir-data --ignore-daemonsets --force
sudo systemctl stop nvidia-persistenced
fuser -k -9 /dev/nvidia*

```


2. Clear any lingering partial MIG slices:
```bash
nvidia-smi mig -dci
nvidia-smi mig -dgi
nvidia-smi -mig 0

```


3. Remove conflicting MIG labels from Kubernetes:
```bash
kubectl label node <node-name> [nvidia.com/mig.config-](https://nvidia.com/mig.config-)
kubectl label node <node-name> [nvidia.com/mig.config.state-](https://nvidia.com/mig.config.state-)

```



---

### 4.2 Operator Validator stuck in `Init:CrashLoopBackOff` or `RunContainerError`

* **Root Cause**: Switching between MIG and non-MIG leaves behind hundreds of stale capability symlinks in `/dev/char` (`/dev/nvidia-caps/*`), causing `toolkit-validation` or device plugin init containers to fail with `file exists`.

**Resolution Steps**:

1. Purge stale symlinks directly on the host:
```bash
find /dev/char/ -lname '*nvidia*' -exec rm -v {} +
udevadm trigger --subsystem-match=char-major

```


2. Restart operator pods:
```bash
kubectl delete pods -n gpu-operator -l app=nvidia-operator-validator
kubectl delete pods -n gpu-operator -l app=nvidia-device-plugin-daemonset
kubectl delete pods -n gpu-operator -l app=gpu-feature-discovery

```



---

### 4.3 NeMo Cache Job Fails: `I/O error No space left on device`

* **Symptom**: Pods named `nemotron-vlm-embedding-ms-cache-job-*` fail with:
```text
ERROR nim_sdk.py:338] Download failed after 1 attempts. Last exception: I/O error No space left on device (os error 28)

```


* **Root Cause**: Downloading weights and generating TensorRT caches for `llama-nemotron-embed-vl-1b-v2` exhausts the cache volume or host storage.

**Resolution Steps**:

1. Delete failed cache jobs and prune container image layers:
```bash
kubectl delete job -n <aiq-namespace> nemotron-vlm-embedding-ms-cache-job
sudo crictl rmi --prune
sudo journalctl --vacuum-size=1G

```


2. Expand the PersistentVolumeClaim (PVC) allocated to the NIM cache to at least **50 GiB**:
```bash
kubectl patch pvc <cache-pvc-name> -n <aiq-namespace> \
  --type='json' \
  -p='[{"op": "replace", "path": "/spec/resources/requests/storage", "value": "50Gi"}]'

```


3. Re-run or upgrade the deployment release.

---

## 5. Network Access & Client DNS Resolution

The frontend service exposes an Ingress hostname at `aiq-frontend.suse.demo`.

### 5.1 Locate Ingress LoadBalancer IP

```bash
kubectl get svc -A | grep -E "LoadBalancer|ingress"

```

### 5.2 Configure Local Hosts Resolution

* **Linux/macOS**: Edit `/etc/hosts`:
```text
<INGRESS_CONTROLLER_IP>   aiq-frontend.suse.demo

```


* **Windows**:
1. Open PowerShell or Notepad as **Administrator**.
2. Edit `C:\Windows\System32\drivers\etc\hosts`.
3. Add the mapping:
```text
<INGRESS_CONTROLLER_IP>   aiq-frontend.suse.demo

```


4. Flush the DNS cache:
```powershell
ipconfig /flushdns

```





Access the UI by navigating to `http://aiq-frontend.suse.demo` in your browser.

```

```
