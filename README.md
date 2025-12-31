# Grafana Mimir Monitoring Stack

A professional Kubernetes monitoring stack using **Grafana Mimir**, **kube-prometheus-stack** (Prometheus Operator), and **SeaweedFS**.

```
┌─────────────────────┐     remote_write     ┌─────────────┐     ┌─────────────────┐
│ Kube-Prometheus-Stack│ ──────────────────>  │    Mimir    │ <── │     Grafana     │
│ (Prometheus Operator)│                      │  (storage)  │     │  (visualization)│
└─────────────────────┘                      └─────────────┘     └─────────────────┘
    (namespace: monitoring)                  (namespace: mimir)          │
           │                                         │                   │
           │                                         ▼                   │
           │                                  ┌─────────────┐            │
           └────────────────────────────────> │  SeaweedFS  │ <──────────┘
                                              │ (S3 storage)│
                                              └─────────────┘
                                           (namespace: seaweedfs)
```

## Components

| Component | Purpose | Version |
|-----------|---------|---------|
| **Kube-Prometheus-Stack** | Prometheus Operator, Grafana, Node Exporter, Kube-State-Metrics | Latest |
| **Grafana Mimir** | Long-term, scalable metrics storage | v3.0.1 |
| **SeaweedFS** | S3-compatible object storage (storage for Mimir) | Latest |
| **Grafana** | Dashboards and visualization (connected to Mimir) | v11.0.0+ |

## Prerequisites

- Kubernetes 1.29+ (tested on Minikube)
- Helm 3.8+
- kubectl configured for your cluster
- Default StorageClass available

## Quick Start

```bash
# Make scripts executable
chmod +x install.sh uninstall.sh

# Install everything
./install.sh
```

## Manual Installation

### Step 1: Add Helm Repositories

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add seaweedfs https://seaweedfs.github.io/seaweedfs/helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### Step 2: Create Namespaces

```bash
kubectl apply -f seaweedfs-namespace.yaml
kubectl apply -f namespace.yaml
kubectl apply -f monitoring-namespace.yaml
```

### Step 3: Deploy SeaweedFS

```bash
# Create S3 credentials secret
kubectl apply -f seaweedfs-s3-secret.yaml

# Patch chart (workaround for fromToml error)
helm pull seaweedfs/seaweedfs --untar
rm seaweedfs/templates/shared/security-configmap.yaml

# Install
helm install seaweedfs ./seaweedfs -n seaweedfs -f seaweedfs-values.yaml

# Wait and create buckets
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=seaweedfs -n seaweedfs --timeout=300s
kubectl apply -f seaweedfs-create-buckets.yaml
```

### Step 4: Deploy Mimir

```bash
helm install mimir grafana/mimir-distributed -n mimir -f mimir-values.yaml
```

### Step 5: Deploy Monitoring Stack (Prometheus Operator)

```bash
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring -f monitoring-values.yaml
```

## Access the Stack

### Grafana Dashboard

```bash
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
```
Open **http://localhost:3000** (credentials: `admin/admin`). 
*Mimir is pre-configured as a data source.*

### Prometheus UI (Local Scraper)

```bash
kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090
```
Open **http://localhost:9090**.

### Mimir API

```bash
kubectl port-forward svc/mimir-gateway -n mimir 8080:80
curl http://localhost:8080/ready
```

## Architecture Details

### Data Flow

1. **Prometheus Operator** (namespace: `monitoring`) automatically discovers targets via **ServiceMonitors** and **PodMonitors** across ALL namespaces.
2. **Prometheus** scrapes metrics and **remote-writes** them to Mimir in the `mimir` namespace at:
   `http://mimir-gateway.mimir.svc.cluster.local:80/api/v1/push`
3. **Mimir** stores metrics in SeaweedFS (S3) in the `seaweedfs` namespace:
   - `mimir-blocks` - Time series data
   - `mimir-ruler` - Recording/alerting rules
   - `mimir-alertmanager` - Alert configs
4. **Grafana** (namespace: `monitoring`) queries **Mimir** (namespace: `mimir`) to show historical and long-term data.

### Endpoints Reference

| Service | Internal URL | External Access |
|---------|--------------|-----------------|
| Mimir Write | `http://mimir-gateway.mimir.svc:80/api/v1/push` | `port-forward :8080` |
| Mimir Query | `http://mimir-gateway.mimir.svc:80/prometheus` | Same as above |
| Prometheus | `http://monitoring-kube-prometheus-prometheus.monitoring.svc:9090` | `port-forward :9090` |
| Grafana | `http://monitoring-grafana.monitoring.svc:80` | `port-forward :3000` |

## Configuration Files

| File | Purpose |
|------|---------|
| `mimir-values.yaml` | Mimir configuration (S3, scaling, limits) |
| `monitoring-values.yaml` | Prometheus Operator & Grafana config (targets all namespaces) |
| `seaweedfs-values.yaml` | SeaweedFS storage configuration |
| `seaweedfs-s3-secret.yaml` | S3 credentials |
| `seaweedfs-create-buckets.yaml` | Job to create Mimir buckets |
| `monitoring-namespace.yaml` | Namespace manifest for the monitoring stack |

## Adding Your Own Scrape Targets

Instead of editing Prometheus config, you now use **ServiceMonitors**:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: my-app-namespace
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
```

## Cleanup

```bash
./uninstall.sh
```

## Troubleshooting

### Check Pod Status
```bash
kubectl get pods -n mimir
kubectl get pods -n monitoring
kubectl get pods -n seaweedfs
```

### View Logs
```bash
# Mimir Ingester
kubectl logs -l app.kubernetes.io/component=ingester -n mimir

# Prometheus
kubectl logs -l app.kubernetes.io/name=prometheus -n monitoring

# Grafana
kubectl logs -l app.kubernetes.io/name=grafana -n monitoring
```

### Test Mimir Directly
```bash
kubectl port-forward svc/mimir-gateway -n mimir 8080:80
curl -s 'http://localhost:8080/prometheus/api/v1/query?query=up' | jq .
```
