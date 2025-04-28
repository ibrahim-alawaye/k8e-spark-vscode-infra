#!/bin/bash

set -e

echo "=== Creating Persistent Volume Claim for Spark ==="

# Create PVC for Spark data
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
      storage: 20Gi
  storageClassName: standard
EOF

echo "PVC created successfully!"