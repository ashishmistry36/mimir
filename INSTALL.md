# Grafana Mimir Installation Guide

This guide installs Grafana Mimir with SeaweedFS as S3-compatible object storage.

## Prerequisites

- Kubernetes 1.29+
- Helm 3.8+
- kubectl configured for your cluster
- Default StorageClass available

## Quick Start

```bash
# Run all steps
./install.sh
```

Or follow the manual steps below.

---

## Step 0: Setup NFS Storage (Optional)

If you don't have a default StorageClass that points to your NFS, you can use the provided template:

```bash
# Update nfs-storage.yaml with your NFS server IP and Path
# Then create the namespace and apply
kubectl create namespace nfs-system
kubectl apply -f nfs-storage.yaml
```

## Step 1: Add Helm Repositories

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add seaweedfs https://seaweedfs.github.io/seaweedfs/helm
helm repo update
```

## Step 2: Create Namespaces

```bash
kubectl apply -f namespace.yaml
kubectl apply -f seaweedfs-namespace.yaml
```

## Step 3: Deploy SeaweedFS

```bash
# Create S3 credentials secret
kubectl apply -f seaweedfs-s3-secret.yaml

# Patch SeaweedFS chart to bypass "fromToml" error (WORKAROUND)
helm pull seaweedfs/seaweedfs --untar
rm seaweedfs/templates/shared/security-configmap.yaml

# Install SeaweedFS from local directory
helm install seaweedfs ./seaweedfs \
  -n seaweedfs \
  -f seaweedfs-values.yaml

# Wait for SeaweedFS to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=seaweedfs -n seaweedfs --timeout=300s

# Create buckets for Mimir
kubectl apply -f seaweedfs-create-buckets.yaml
```

## Step 4: Deploy Mimir

```bash
helm install mimir grafana/mimir-distributed \
  -n mimir \
  -f mimir-values.yaml

# Watch pods start up
kubectl get pods -n mimir -w
```

## Step 5: Verify Installation

```bash
# Check all pods are running
kubectl get pods -n mimir
kubectl get pods -n seaweedfs

# Test Mimir readiness
kubectl port-forward svc/mimir-nginx -n mimir 8080:80 &
curl http://localhost:8080/ready
```

---

## Endpoints

| Service | Internal URL | Port Forward Command |
|---------|--------------|----------------------|
| Mimir Write | `http://mimir-nginx.mimir.svc:80/api/v1/push` | `kubectl port-forward svc/mimir-nginx -n mimir 8080:80` |
| Mimir Query | `http://mimir-nginx.mimir.svc:80/prometheus` | Same as above |
| SeaweedFS S3 | `http://seaweedfs-s3.seaweedfs.svc:8333` | `kubectl port-forward svc/seaweedfs-s3 -n seaweedfs 8333:8333` |

---

## Configure Prometheus to Send Metrics

Add to your Prometheus configuration:

```yaml
remote_write:
  - url: http://mimir-nginx.mimir.svc.cluster.local:80/api/v1/push
```

Or for Grafana Alloy:

```alloy
prometheus.remote_write "mimir" {
  endpoint {
    url = "http://mimir-nginx.mimir.svc.cluster.local:80/api/v1/push"
  }
}
```

---

## Grafana Data Source

Add Mimir as a Prometheus data source in Grafana:

- **URL**: `http://mimir-nginx.mimir.svc.cluster.local:80/prometheus`
- **Type**: Prometheus

---

## Cleanup

```bash
helm uninstall mimir -n mimir
helm uninstall seaweedfs -n seaweedfs
kubectl delete -f seaweedfs-s3-secret.yaml
kubectl delete namespace mimir seaweedfs
```

---

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n mimir
kubectl logs <pod-name> -n mimir
```

### S3 connection issues
```bash
# Verify SeaweedFS S3 is accessible
kubectl exec -it deploy/mimir-distributor -n mimir -- \
  wget -qO- http://seaweedfs-s3.seaweedfs.svc:8333
```

### Check buckets exist
```bash
kubectl logs job/seaweedfs-create-buckets -n seaweedfs
```
