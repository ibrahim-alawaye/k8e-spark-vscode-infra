#!/bin/bash

echo "=== Installing MicroK8s ==="

# Install MicroK8s
sudo snap install microk8s --classic

# Add current user to microk8s group
sudo usermod -aG microk8s $USER

# Create .kube directory if it doesn't exist
mkdir -p ~/.kube

# Set ownership of the .kube directory
sudo chown -R $USER ~/.kube

# Wait for MicroK8s to be ready
echo "Waiting for MicroK8s to be ready..."
microk8s status --wait-ready

# Create an alias for kubectl
echo 'alias kubectl="microk8s kubectl"' >> ~/.bashrc

# Configure MicroK8s to be accessible via kubectl
microk8s config > ~/.kube/config

echo "MicroK8s installed successfully!"
echo "NOTE: You may need to log out and log back in for group changes to take effect."