#!/bin/bash

set -e

echo "=== Enabling MicroK8s addons ==="

# Verify MicroK8s is running properly
echo "Verifying MicroK8s API server..."
if ! microk8s kubectl get nodes &> /dev/null; then
    echo "Error: MicroK8s API server is not responding. Attempting to fix..."
    sudo microk8s stop
    sudo microk8s reset
    sudo microk8s start
    sleep 10
    if ! microk8s kubectl get nodes &> /dev/null; then
        echo "Error: MicroK8s API server is still not responding after reset."
        echo "Please check the logs with: sudo journalctl -u snap.microk8s.daemon-kubelite -n 100"
        exit 1
    fi
fi

# Configure IPtables for Kubernetes
echo "Configuring IPtables FORWARD policy..."
sudo iptables -P FORWARD ACCEPT

# Make IPtables configuration persistent
if ! command -v iptables-persistent &> /dev/null; then
    echo "Installing iptables-persistent..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
else
    echo "Saving current iptables rules..."
    sudo netfilter-persistent save
fi

# Configure Docker to use MicroK8s registry
echo "Configuring Docker to use MicroK8s registry..."
sudo mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
    sudo bash -c 'cat > /etc/docker/daemon.json << EOF
{
    "insecure-registries" : ["localhost:32000"]
}
EOF'
    sudo systemctl restart docker
elif ! grep -q "insecure-registries" /etc/docker/daemon.json; then
    # Backup existing file
    sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
    # Add insecure-registries if not present
    if command -v jq &> /dev/null; then
        sudo bash -c 'jq ". += {\"insecure-registries\": [\"localhost:32000\"]}" /etc/docker/daemon.json > /tmp/daemon.json && mv /tmp/daemon.json /etc/docker/daemon.json'
    else
        echo "jq not found, installing..."
        sudo apt-get update && sudo apt-get install -y jq
        sudo bash -c 'jq ". += {\"insecure-registries\": [\"localhost:32000\"]}" /etc/docker/daemon.json > /tmp/daemon.json && mv /tmp/daemon.json /etc/docker/daemon.json'
    fi
    sudo systemctl restart docker
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
ADDONS=("dns" "dashboard" "metrics-server" "storage" "registry" "rbac")

for addon in "${ADDONS[@]}"; do
    enable_addon $addon
done

# Create dashboard admin user and get token
echo "Creating dashboard admin user and generating token..."
cat <<EOF | microk8s kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kube-system
EOF

# Wait for the service account to be created
sleep 5

# Get the token and save it to a file
echo "Retrieving dashboard token..."
TOKEN_FILE="./dashboard-token.txt"

# For Kubernetes 1.24+
if microk8s kubectl -n kube-system get serviceaccount admin-user &> /dev/null; then
    # Create a token for the admin-user service account
    cat <<EOF | microk8s kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: admin-user-token
  namespace: kube-system
  annotations:
    kubernetes.io/service-account.name: admin-user
type: kubernetes.io/service-account-token
EOF
    
    # Wait for the token to be created
    sleep 5
    
    # Get the token
    TOKEN=$(microk8s kubectl -n kube-system get secret admin-user-token -o jsonpath='{.data.token}' | base64 --decode)
    echo "$TOKEN" > "$TOKEN_FILE"
    echo "Dashboard token saved to $TOKEN_FILE"
    echo "Use this token to log in to the Kubernetes Dashboard at:"
    echo "https://localhost:10443/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/"
else
    echo "Error: admin-user service account not found. Token creation failed."
fi

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
    
    # Install MinIO with specific configuration for resource-constrained environments
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

# Verify that the CNI is working properly
echo "Verifying CNI functionality..."
if ! microk8s kubectl get nodes -o wide | grep -q "Ready"; then
    echo "Warning: Nodes are not in Ready state. CNI might not be functioning properly."
    echo "Checking CNI pods..."
    microk8s kubectl get pods -n kube-system | grep -E 'calico|flannel|cni'
else
    echo "CNI appears to be functioning properly."
fi

echo "MicroK8s addons setup completed."
