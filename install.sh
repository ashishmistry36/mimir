#!/bin/bash
# Mimir Stack Installation Script
# Deploys: SeaweedFS (S3) -> Mimir -> Kube-Prometheus-Stack

set -e

echo "=== Mimir Monitoring Stack Installation (Operator Version) ==="
echo ""
echo "Components:"
echo "  - SeaweedFS (S3-compatible object storage)"
echo "  - Mimir (long-term metrics storage)"
echo "  - Kube-Prometheus-Stack (Prometheus Operator, Grafana, Node Exporter)"
echo ""

# Wait for potential deletions from uninstall.sh
echo "Ensuring namespaces are clean..."
kubectl delete namespace mimir monitoring seaweedfs --ignore-not-found --wait=true || true

# Add Helm repos
echo "Step 1: Adding Helm repositories..."
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo add seaweedfs https://seaweedfs.github.io/seaweedfs/helm || true
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update

# Create namespaces and storage classes
echo ""
echo "Step 2: Creating namespaces and storage classes..."
kubectl apply -f storage-classes.yaml
kubectl apply -f seaweedfs-namespace.yaml
kubectl apply -f namespace.yaml
kubectl apply -f monitoring-namespace.yaml

# Deploy SeaweedFS
echo ""
echo "Step 3: Deploying SeaweedFS..."
kubectl apply -f seaweedfs-s3-secret.yaml

# Always use a fresh SeaweedFS chart to ensure clean templates
echo "Downloading and patching fresh SeaweedFS chart..."
rm -rf ./seaweedfs
helm pull seaweedfs/seaweedfs --untar
rm -f seaweedfs/templates/shared/security-configmap.yaml

# Check if SeaweedFS is already installed
if helm status seaweedfs -n seaweedfs &>/dev/null; then
    echo "SeaweedFS already installed, upgrading..."
    helm upgrade seaweedfs ./seaweedfs \
      -n seaweedfs \
      -f seaweedfs-values.yaml
else
    helm install seaweedfs ./seaweedfs \
      -n seaweedfs \
      -f seaweedfs-values.yaml
fi

echo "Waiting for SeaweedFS to be ready..."
# Wait for pods to at least exist
sleep 10
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=seaweedfs -n seaweedfs --timeout=300s || true
sleep 30

# Create buckets
echo ""
echo "Step 4: Creating S3 buckets..."
# Delete old job if it exists
kubectl delete job seaweedfs-create-buckets -n seaweedfs --ignore-not-found
kubectl apply -f seaweedfs-create-buckets.yaml

# Wait for bucket creation
echo "Waiting for bucket creation job..."
sleep 45

# Deploy Mimir
echo ""
echo "Step 5: Deploying Mimir..."
if helm status mimir -n mimir &>/dev/null; then
    echo "Mimir already installed, upgrading..."
    helm upgrade mimir grafana/mimir-distributed \
      -n mimir \
      -f mimir-values.yaml
else
    helm install mimir grafana/mimir-distributed \
      -n mimir \
      -f mimir-values.yaml
fi

echo "Waiting for Mimir to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=mimir -n mimir --timeout=600s || true

# Deploy Kube-Prometheus-Stack
echo ""
echo "Step 6: Deploying Kube-Prometheus-Stack..."
if helm status monitoring -n monitoring &>/dev/null; then
    echo "Monitoring stack already installed, upgrading..."
    helm upgrade monitoring prometheus-community/kube-prometheus-stack \
      -n monitoring \
      -f monitoring-values.yaml
else
    helm install monitoring prometheus-community/kube-prometheus-stack \
      -n monitoring \
      -f monitoring-values.yaml
fi

# Show status
echo ""
echo "=== Installation Complete ==="
echo ""
echo "Pod Status:"
kubectl get pods -n mimir
echo ""
kubectl get pods -n seaweedfs
echo ""
kubectl get pods -n monitoring
echo ""

echo "=== Access Instructions ==="
echo ""
echo "Grafana (admin/admin):"
echo "  kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"
echo "  Open http://localhost:3000"
echo ""
echo "Prometheus (Local Scraper):"
echo "  kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090"
echo "  Open http://localhost:9090"
echo ""
echo "Mimir API:"
echo "  kubectl port-forward svc/mimir-gateway -n mimir 8080:80"
echo "  curl http://localhost:8080/ready"
echo ""
