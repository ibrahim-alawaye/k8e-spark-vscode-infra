#!/bin/bash

set -e

echo "=== Creating Persistent Volume Claim for Spark ==="

# Check if PVC already exists
if kubectl get pvc spark-data-pvc -n spark-cluster &>/dev/null; then
    echo "PVC 'spark-data-pvc' already exists in namespace 'spark-cluster'."
    echo "To recreate it, first delete the existing PVC with:"
    echo "kubectl delete pvc spark-data-pvc -n spark-cluster"
    exit 0
fi

# Check if namespace exists
if ! kubectl get namespace spark-cluster &>/dev/null; then
    echo "Creating namespace 'spark-cluster'..."
    kubectl create namespace spark-cluster
fi

# Create PVC for Spark data with reduced size for laptop usage
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: spark-data-pvc
  namespace: spark-cluster
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: standard
EOF

# Verify PVC was created
if kubectl get pvc spark-data-pvc -n spark-cluster &>/dev/null; then
    echo "PVC created successfully!"
    echo "Details:"
    kubectl get pvc spark-data-pvc -n spark-cluster -o wide
else
    echo "Error: Failed to create PVC."
    exit 1
fi
