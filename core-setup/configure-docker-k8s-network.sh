#!/bin/bash

set -e

echo "=== Configuring Docker and Kubernetes networking ==="

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if Docker is running
log "Checking if Docker is running..."
if ! docker info > /dev/null 2>&1; then
    log "Error: Docker is not running. Attempting to start Docker..."
    if command_exists systemctl; then
        sudo systemctl start docker
        sleep 5
        if ! docker info > /dev/null 2>&1; then
            log "Error: Failed to start Docker. Please check Docker installation."
            exit 1
        fi
        log "Docker started successfully."
    else
        log "Error: Cannot start Docker automatically. Please start Docker manually."
        exit 1
    fi
fi

# Define custom subnet for k8s-network to avoid conflicts
K8S_NETWORK_SUBNET="172.18.0.0/16"

# Check if k8s-network already exists
if docker network inspect k8s-network > /dev/null 2>&1; then
    log "Docker k8s-network already exists, checking its configuration..."
    CURRENT_SUBNET=$(docker network inspect k8s-network -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
    log "Current k8s-network subnet: ${CURRENT_SUBNET}"
    
    if [ "$CURRENT_SUBNET" != "$K8S_NETWORK_SUBNET" ]; then
        log "Subnet mismatch. Removing existing network and recreating with correct subnet..."
        docker network rm k8s-network
        docker network create k8s-network --subnet=$K8S_NETWORK_SUBNET
        log "Docker k8s-network recreated with subnet $K8S_NETWORK_SUBNET"
    else
        log "Docker k8s-network has correct subnet, skipping recreation."
    fi
else
    log "Creating Docker k8s-network with subnet $K8S_NETWORK_SUBNET..."
    docker network create k8s-network --subnet=$K8S_NETWORK_SUBNET
    log "Docker k8s-network created successfully."
fi

# Get the Docker bridge network subnet
DOCKER_SUBNET=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
log "Detected Docker bridge subnet: ${DOCKER_SUBNET}"

# Check if MicroK8s is installed
if ! command_exists microk8s; then
    log "Error: MicroK8s is not installed. Please install MicroK8s first."
    exit 1
fi

# Check if MicroK8s is running
log "Checking if MicroK8s is running..."
if ! microk8s status | grep "microk8s is running" > /dev/null; then
    log "MicroK8s is not running. Attempting to start MicroK8s..."
    sudo microk8s start
    sleep 10
    
    if ! microk8s status | grep "microk8s is running" > /dev/null; then
        log "Error: Failed to start MicroK8s. Please check MicroK8s installation."
        exit 1
    fi
    log "MicroK8s started successfully."
fi

# Configure IPtables for Kubernetes
log "Configuring IPtables FORWARD policy..."
sudo iptables -P FORWARD ACCEPT

# Make IPtables configuration persistent
if ! command_exists iptables-persistent; then
    log "Installing iptables-persistent..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
else
    log "Saving current iptables rules..."
    sudo netfilter-persistent save
fi

# Create a backup of the current kube-proxy configuration if it exists
KUBE_PROXY_CONFIG="/var/snap/microk8s/current/args/kube-proxy"
if [ -f "$KUBE_PROXY_CONFIG" ]; then
    log "Creating backup of current kube-proxy configuration..."
    sudo cp "$KUBE_PROXY_CONFIG" "${KUBE_PROXY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
fi

# Check if kube-proxy config already has our non-masquerade-cidr
CURRENT_CONFIG=""
if [ -f "$KUBE_PROXY_CONFIG" ]; then
    CURRENT_CONFIG=$(cat "$KUBE_PROXY_CONFIG")
fi

# Combine both Docker bridge and k8s-network subnets for non-masquerade-cidr
NON_MASQUERADE_CIDRS="${DOCKER_SUBNET},${K8S_NETWORK_SUBNET}"

if echo "$CURRENT_CONFIG" | grep -q "${NON_MASQUERADE_CIDRS}"; then
    log "MicroK8s kube-proxy already configured with correct subnets, skipping configuration."
else
    log "Configuring MicroK8s kube-proxy to allow communication with Docker networks..."
    
    # Create the kube-proxy configuration with proper line breaks
    cat <<EOF | sudo tee "$KUBE_PROXY_CONFIG"
--proxy-mode=iptables
--cluster-cidr=10.1.0.0/16
--hostname-override=\$(hostname)
--kubeconfig=/var/snap/microk8s/current/credentials/proxy.config
--logtostderr=true
--v=4
--iptables-min-sync-period=1s
--iptables-sync-period=10s
--non-masquerade-cidr=${NON_MASQUERADE_CIDRS}
EOF

    log "MicroK8s kube-proxy configuration updated."
    
    # Restart MicroK8s to apply changes
    log "Restarting MicroK8s to apply changes..."
    sudo microk8s stop
    
    # Wait for MicroK8s to fully stop
    log "Waiting for MicroK8s to fully stop..."
    STOP_TIMEOUT=30
    STOP_ELAPSED=0
    while [ $STOP_ELAPSED -lt $STOP_TIMEOUT ]; do
        if ! systemctl is-active --quiet snap.microk8s.daemon-kubelite; then
            log "MicroK8s has stopped."
            break
        fi
        sleep 2
        STOP_ELAPSED=$((STOP_ELAPSED+2))
        log "Still waiting for MicroK8s to stop... ($STOP_ELAPSED seconds elapsed)"
    done
    
    if [ $STOP_ELAPSED -ge $STOP_TIMEOUT ]; then
        log "Warning: Timeout waiting for MicroK8s to stop. Forcing stop..."
        sudo systemctl stop snap.microk8s.daemon-kubelite
        sudo systemctl stop snap.microk8s.daemon-containerd
        sudo systemctl stop snap.microk8s.daemon-apiserver-kicker
        sleep 5
    fi
    
    # Start MicroK8s
    log "Starting MicroK8s..."
    sudo microk8s start
    
    # Wait for MicroK8s to be ready again with a timeout
    log "Waiting for MicroK8s to restart (timeout: 180s)..."
    
    TIMEOUT=180
    ELAPSED=0
    while [ $ELAPSED -lt $TIMEOUT ]; do
        if microk8s status | grep "microk8s is running" > /dev/null; then
            log "MicroK8s is running."
            break
        fi
        sleep 5
        ELAPSED=$((ELAPSED+5))
        log "Still waiting... ($ELAPSED seconds elapsed)"
    done
    
    if [ $ELAPSED -ge $TIMEOUT ]; then
        log "Warning: Timeout waiting for MicroK8s to restart. Attempting to diagnose issues..."
        sudo journalctl -u snap.microk8s.daemon-kubelite -n 50
        log "Please check MicroK8s status manually with 'microk8s inspect'."
    fi
fi

# Configure Docker to use MicroK8s registry
log "Configuring Docker to use MicroK8s registry..."
sudo mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
    sudo bash -c 'cat > /etc/docker/daemon.json << EOF
{
    "insecure-registries" : ["localhost:32000"]
}
EOF'
    log "Docker daemon.json created. Restarting Docker..."
    sudo systemctl restart docker
    sleep 5
elif ! grep -q "insecure-registries" /etc/docker/daemon.json; then
    # Backup existing file
    sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
    # Add insecure-registries if not present
    if command_exists jq; then
        sudo bash -c 'jq ". += {\"insecure-registries\": [\"localhost:32000\"]}" /etc/docker/daemon.json > /tmp/daemon.json && mv /tmp/daemon.json /etc/docker/daemon.json'
    else
        log "jq not found, installing..."
        sudo apt-get update && sudo apt-get install -y jq
        sudo bash -c 'jq ". += {\"insecure-registries\": [\"localhost:32000\"]}" /etc/docker/daemon.json > /tmp/daemon.json && mv /tmp/daemon.json /etc/docker/daemon.json'
    fi
    log "Updated Docker daemon.json. Restarting Docker..."
    sudo systemctl restart docker
    sleep 5
else
    log "Docker already configured to use MicroK8s registry."
fi

# Verify Docker configuration
log "Verifying Docker configuration..."
if docker info | grep -q "localhost:32000"; then
    log "Docker is correctly configured to use MicroK8s registry."
else
    log "Warning: Docker might not be correctly configured to use MicroK8s registry."
fi

# Wait for Kubernetes API to be accessible
log "Waiting for Kubernetes API to be accessible (timeout: 60s)..."
API_TIMEOUT=60
API_ELAPSED=0
while [ $API_ELAPSED -lt $API_TIMEOUT ]; do
    if microk8s kubectl get nodes > /dev/null 2>&1; then
        log "Kubernetes API is accessible."
        break
    fi
    sleep 5
    API_ELAPSED=$((API_ELAPSED+5))
    log "Still waiting for Kubernetes API... ($API_ELAPSED seconds elapsed)"
done

if [ $API_ELAPSED -ge $API_TIMEOUT ]; then
    log "Warning: Cannot connect to Kubernetes API after $API_TIMEOUT seconds."
    log "Attempting to diagnose issues..."
    
    # Check if API server is running
    if systemctl is-active --quiet snap.microk8s.daemon-kubelite; then
        log "MicroK8s daemon is running."
    else
        log "MicroK8s daemon is not running. Attempting to start..."
        sudo microk8s start
    fi
    
    # Check if API server port is open
    if command_exists netstat; then
        log "Checking if API server port is open..."
        sudo netstat -tulpn | grep 16443
    fi
    
    log "You may need to restart MicroK8s manually with 'sudo microk8s stop && sudo microk8s start'."
    log "If issues persist, try resetting MicroK8s with 'sudo microk8s reset'."
else
    # Verify connectivity between Docker and Kubernetes
    log "Verifying connectivity between Docker and Kubernetes..."
    
    # Create a test pod in Kubernetes
    log "Creating a test pod in Kubernetes..."
    cat <<EOF | microk8s kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: network-test
  labels:
    app: network-test
spec:
  containers:
  - name: network-test
    image: busybox
    command: ['sh', '-c', 'echo The network test pod is running && sleep 3600']
EOF
    
    # Wait for the pod to be running
    log "Waiting for test pod to be running..."
    POD_TIMEOUT=60
    POD_ELAPSED=0
    while [ $POD_ELAPSED -lt $POD_TIMEOUT ]; do
        if microk8s kubectl get pod network-test | grep -q "Running"; then
            log "Test pod is running."
            break
        fi
        sleep 5
        POD_ELAPSED=$((POD_ELAPSED+5))
        log "Still waiting for test pod... ($POD_ELAPSED seconds elapsed)"
    done
    
    if [ $POD_ELAPSED -ge $POD_TIMEOUT ]; then
        log "Warning: Test pod did not start within $POD_TIMEOUT seconds."
        microk8s kubectl describe pod network-test
    else
        log "Test pod started successfully. Cleaning up..."
        microk8s kubectl delete pod network-test
    fi
fi

log "Docker and Kubernetes networking configuration completed."
log "To verify the setup, try running a container in the k8s-network and accessing the Kubernetes API:"
log "  docker run --rm --network=k8s-network busybox wget -q -O- http://host.docker.internal:16443"
