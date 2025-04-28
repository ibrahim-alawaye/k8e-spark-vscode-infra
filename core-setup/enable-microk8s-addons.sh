#!/bin/bash

echo "=== Enabling MicroK8s addons ==="

# Enable necessary addons
microk8s enable dns
microk8s enable dashboard
microk8s enable storage
microk8s enable registry
microk8s enable metrics-server
microk8s enable prometheus
microk8s enable grafana

# Install MinIO using Helm
echo "Installing MinIO..."
microk8s kubectl create namespace minio
microk8s helm repo add minio https://charts.min.io/
microk8s helm install minio minio/minio --namespace minio --set resources.requests.memory=512Mi --set persistence.size=10Gi --set mode=standalone

# Wait for deployments to be ready
echo "Waiting for deployments to be ready..."
microk8s kubectl wait --for=condition=available --timeout=300s deployment/kubernetes-dashboard -n kube-system
microk8s kubectl wait --for=condition=available --timeout=300s deployment/grafana -n observability
microk8s kubectl wait --for=condition=available --timeout=300s deployment/prometheus-k8s -n observability
microk8s kubectl wait --for=condition=available --timeout=300s deployment/minio -n minio

echo "MicroK8s addons enabled successfully!"