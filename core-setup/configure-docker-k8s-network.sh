#!/bin/bash

echo "=== Configuring Docker and Kubernetes networking ==="

# Create a Docker network for Kubernetes
docker network create k8s-network || true

# Get the Docker bridge network subnet
DOCKER_SUBNET=$(docker network inspect bridge -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}')

# Configure MicroK8s to allow communication with Docker network
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

# Restart MicroK8s to apply changes
sudo microk8s stop
sudo microk8s start

# Wait for MicroK8s to be ready again
echo "Waiting for MicroK8s to restart..."
microk8s status --wait-ready

echo "Docker and Kubernetes networking configured successfully!"