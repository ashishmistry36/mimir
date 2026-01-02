#!/bin/bash
# Mimir Stack Uninstallation Script

set -e

echo "=== Mimir Monitoring Stack Uninstallation ==="
echo ""

# Uninstall Monitoring Stack
echo "Step 1: Removing Kube-Prometheus-Stack..."
helm uninstall monitoring -n monitoring || true

# Uninstall Mimir
echo ""
echo "Step 2: Uninstalling Mimir..."
helm uninstall mimir -n mimir || true

# Uninstall SeaweedFS
echo ""
echo "Step 3: Uninstalling SeaweedFS..."
helm uninstall seaweedfs -n mimir || true

# Delete secrets and jobs
echo ""
echo "Step 4: Removing secrets and jobs..."
kubectl delete -f seaweedfs-s3-secret.yaml --ignore-not-found
kubectl delete -f seaweedfs-create-buckets.yaml --ignore-not-found

# Delete namespaces (this will delete all remaining resources)
echo ""
echo "Step 5: Deleting namespaces..."
kubectl delete namespace mimir --ignore-not-found
kubectl delete namespace monitoring --ignore-not-found

echo ""
echo "=== Uninstallation Complete ==="
