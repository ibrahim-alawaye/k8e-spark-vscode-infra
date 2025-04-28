#!/bin/bash

echo "=== Installing Helm ==="

# Download and install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Configure Helm to use MicroK8s
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
source ~/.bashrc

echo "Helm installed successfully!"