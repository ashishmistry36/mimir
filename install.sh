#!/bin/bash
# Mimir + SeaweedFS Installation Script

set -e

echo "=== Mimir Installation Script ==="
echo ""

# Add Helm repos
echo "Step 1: Adding Helm repositories..."
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add seaweedfs https://seaweedfs.github.io/seaweedfs/helm
helm repo update

# Create namespaces
echo ""
echo "Step 2: Creating namespaces..."
kubectl apply -f seaweedfs-namespace.yaml
kubectl apply -f namespace.yaml
# Optional: Setup NFS storage if needed
# kubectl create namespace nfs-system
# kubectl apply -f nfs-storage.yaml

# Deploy SeaweedFS
echo ""
echo "Step 3: Deploying SeaweedFS..."
kubectl apply -f seaweedfs-s3-secret.yaml

# WORKAROUND for "fromToml" error in some Helm versions
echo "Patching SeaweedFS chart to bypass fromToml error..."
helm pull seaweedfs/seaweedfs --untar
rm seaweedfs/templates/shared/security-configmap.yaml

helm install seaweedfs ./seaweedfs \
  -n seaweedfs \
  -f seaweedfs-values.yaml

echo "Waiting for SeaweedFS to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=seaweedfs -n seaweedfs --timeout=300s || true
sleep 30

# Create buckets
echo ""
echo "Step 4: Creating S3 buckets..."
kubectl apply -f seaweedfs-create-buckets.yaml

# Wait for bucket creation
echo "Waiting for bucket creation job..."
sleep 45

# Deploy Mimir
echo ""
echo "Step 5: Deploying Mimir..."
helm install mimir grafana/mimir-distributed \
  -n mimir \
  -f mimir-values.yaml

echo ""
echo "Step 6: Waiting for Mimir pods..."
kubectl get pods -n mimir

echo ""
echo "=== Installation Complete ==="
echo ""
echo "Monitor progress with:"
echo "  kubectl get pods -n mimir -w"
echo "  kubectl get pods -n seaweedfs -w"
echo ""
echo "Test Mimir:"
echo "  kubectl port-forward svc/mimir-nginx -n mimir 8080:80"
echo "  curl http://localhost:8080/ready"
