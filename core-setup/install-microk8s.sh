#!/bin/bash

set -e

echo "=== Checking MicroK8s installation ==="

# Check if MicroK8s is already installed
if command -v microk8s &> /dev/null; then
    echo "MicroK8s is already installed."
    
    # Check if an update is available
    if sudo snap refresh --list | grep -q microk8s; then
        echo "An update is available for MicroK8s. Updating..."
        sudo snap refresh microk8s --classic
        echo "MicroK8s updated successfully."
    else
        echo "MicroK8s is up to date."
    fi
else
    echo "Installing MicroK8s..."
    sudo snap install microk8s --classic
    echo "MicroK8s installed successfully."
fi

# Check if current user is in microk8s group
if groups $USER | grep -q '\bmicrok8s\b'; then
    echo "User $USER is already in the microk8s group."
else
    echo "Adding user $USER to the microk8s group..."
    sudo usermod -aG microk8s $USER
    echo "User added to microk8s group. You may need to log out and log back in for this to take effect."
fi

# Ensure .kube directory exists and has correct permissions
if [ ! -d "$HOME/.kube" ]; then
    mkdir -p $HOME/.kube
fi
sudo chown -R $USER:$USER $HOME/.kube

# Wait for MicroK8s to be ready with a timeout
echo "Waiting for MicroK8s to be ready (timeout: 120s)..."
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
    echo "Warning: Timeout waiting for MicroK8s to be ready. Please check MicroK8s status manually."
else
    # Generate and set up kubeconfig
    echo "Setting up kubectl configuration..."
    microk8s config > $HOME/.kube/config
    chmod 600 $HOME/.kube/config
    
    echo "MicroK8s setup completed."
fi
