#!/bin/bash

set -e

echo "=== Enabling MicroK8s addons ==="

# Check if MicroK8s is running
if ! microk8s status | grep "microk8s is running" > /dev/null; then
    echo "Error: MicroK8s is not running. Please start MicroK8s first."
    exit 1
fi

# Function to enable an addon with retry logic
enable_addon() {
    local addon=$1
    local max_attempts=3
    local attempt=1
    local success=false
    
    echo "Checking addon: $addon"
    
    # Check if addon is already enabled
    if microk8s status | grep -q "$addon *# .* enabled"; then
        echo "Addon $addon is already enabled."
        return 0
    fi
    
    echo "Enabling addon: $addon"
    
    while [ $attempt -le $max_attempts ] && [ "$success" = "false" ]; do
        echo "Attempt $attempt of $max_attempts to enable $addon..."
        
        if microk8s enable $addon; then
            success=true
            echo "Successfully enabled $addon."
        else
            echo "Failed to enable $addon on attempt $attempt."
            attempt=$((attempt+1))
            [ $attempt -le $max_attempts ] && sleep 10
        fi
    done
    
    if [ "$success" = "false" ]; then
        echo "Warning: Failed to enable $addon after $max_attempts attempts."
        return 1
    fi
    
    return 0
}

# Enable core addons
ADDONS=("dns" "dashboard" "metrics-server" "storage" "registry")

for addon in "${ADDONS[@]}"; do
    enable_addon $addon
done

# Enable MinIO with specific configuration if not already installed
if ! microk8s kubectl get namespace minio &> /dev/null; then
    echo "Installing MinIO..."
    
    # Create namespace
    microk8s kubectl create namespace minio
    
    # Add Bitnami repo if not already added
    if ! helm repo list | grep -q "bitnami"; then
        helm repo add bitnami https://charts.bitnami.com/bitnami
        helm repo update
    fi
    
    # Install MinIO with specific configuration
    # helm install minio bitnami/minio \
    #     --namespace minio \
    #     --set resources.requests.memory=512Mi \
    #     --set persistence.size=2Ti \
    #     --set mode=standalone
    helm install minio bitnami/minio \
        --namespace minio \
        --set resources.requests.memory=256Mi \
        --set resources.limits.memory=512Mi \
        --set resources.requests.cpu=100m \
        --set resources.limits.cpu=500m \
        --set persistence.size=10Gi \
        --set mode=standalone 

    echo "MinIO installed successfully."
else
    echo "MinIO is already installed."
fi

# Wait for deployments to be ready
echo "Waiting for deployments to be ready..."
DEPLOYMENTS=("kubernetes-dashboard" "metrics-server" "minio")

for deployment in "${DEPLOYMENTS[@]}"; do
    echo "Checking deployment: $deployment"
    
    # Get the namespace for the deployment
    NAMESPACE=""
    if [ "$deployment" = "kubernetes-dashboard" ]; then
        NAMESPACE="kube-system"
    elif [ "$deployment" = "metrics-server" ]; then
        NAMESPACE="kube-system"
    elif [ "$deployment" = "minio" ]; then
        NAMESPACE="minio"
    fi
    
    if [ -n "$NAMESPACE" ]; then
        # Check if deployment exists
        if microk8s kubectl get deployment $deployment -n $NAMESPACE &> /dev/null; then
            echo "Waiting for deployment $deployment in namespace $NAMESPACE to be ready..."
            microk8s kubectl rollout status deployment $deployment -n $NAMESPACE --timeout=120s || echo "Warning: Timeout waiting for $deployment to be ready."
        else
            echo "Deployment $deployment not found in namespace $NAMESPACE."
        fi
    fi
done

echo "MicroK8s addons setup completed."
