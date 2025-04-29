#!/bin/bash

set -e

echo "=== Starting installation of MicroK8s, Docker, and Kubernetes tools ==="

# Make all scripts executable
chmod +x ./*.sh

# Run installation scripts in sequence
./install-docker.sh
./install-microk8s.sh
./install-helm.sh
./enable-microk8s-addons.sh
./configure-docker-k8s-network.sh

echo "=== Installation complete! ==="
echo "You can access:"
echo "- Kubernetes Dashboard: https://localhost:10443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/"
echo "- MinIO: http://localhost:9000"
echo ""
echo "To get the MinIO credentials:"
echo "  Username: $(microk8s kubectl get secret --namespace minio minio -o jsonpath="{.data.rootUser}" | base64 --decode)"
echo "  Password: $(microk8s kubectl get secret --namespace minio minio -o jsonpath="{.data.rootPassword}" | base64 --decode)"
echo ""
echo "Use 'microk8s kubectl get all --all-namespaces' to see all resources"
