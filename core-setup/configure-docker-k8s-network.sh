#!/bin/bash

set -e

echo "=== Configuring Docker and Kubernetes networking ==="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker first."
    exit 1
fi

# Check if k8s-network already exists
if docker network inspect k8s-network > /dev/null 2>&1; then
    echo "Docker k8s-network already exists, skipping creation."
else
    echo "Creating Docker k8s-network..."
    docker network create k8s-network
    echo "Docker k8s-network created successfully."
fi

# Get the Docker bridge network subnet
DOCKER_SUBNET=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
echo "Detected Docker bridge subnet: ${DOCKER_SUBNET}"

# Check if MicroK8s is running
if ! microk8s status | grep "microk8s is running" > /dev/null; then
    echo "Error: MicroK8s is not running. Please start MicroK8s first."
    exit 1
fi

# Check if kube-proxy config already has our non-masquerade-cidr
CURRENT_CONFIG=""
if [ -f "/var/snap/microk8s/current/args/kube-proxy" ]; then
    CURRENT_CONFIG=$(cat /var/snap/microk8s/current/args/kube-proxy)
fi

if echo "$CURRENT_CONFIG" | grep -q "${DOCKER_SUBNET}"; then
    echo "MicroK8s kube-proxy already configured with correct Docker subnet, skipping configuration."
else
    echo "Configuring MicroK8s kube-proxy to allow communication with Docker network..."
    
    # Create the kube-proxy configuration with proper line breaks
    cat <<EOF | sudo tee /var/snap/microk8s/current/args/kube-proxy
--proxy-mode=iptables
--cluster-cidr=10.1.0.0/16
--hostname-override=\$(hostname)
--kubeconfig=/var/snap/microk8s/current/credentials/proxy.config
--logtostderr=true
--v=4
--iptables-min-sync-period=1s
--iptables-sync-period=10s
--non-masquerade-cidr=${DOCKER_SUBNET}
EOF

    echo "MicroK8s kube-proxy configuration updated."
    
    # Restart MicroK8s to apply changes
    echo "Restarting MicroK8s to apply changes..."
    sudo microk8s stop
    sleep 5
    sudo microk8s start
    
    # Wait for MicroK8s to be ready again with a timeout
    echo "Waiting for MicroK8s to restart (timeout: 120s)..."
    
    TIMEOUT=120
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if microk8s status | grep "microk8s is running" > /dev/null; then
            echo "MicroK8s is running."
            break
        fi
        sleep 5
        ELAPSED=$((ELAPSED+5))
        echo "Still waiting... ($ELAPSED seconds elapsed)"
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo "Warning: Timeout waiting for MicroK8s to restart. Please check MicroK8s status manually."
    fi
fi

# Verify connectivity
echo "Verifying Kubernetes API connectivity..."
if microk8s kubectl get nodes > /dev/null 2>&1; then
    echo "Kubernetes API is accessible."
else
    echo "Warning: Cannot connect to Kubernetes API. You may need to restart MicroK8s manually."
fi

echo "Docker and Kubernetes networking configuration completed."
