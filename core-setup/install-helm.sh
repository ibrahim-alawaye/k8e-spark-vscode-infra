#!/bin/bash

set -e

echo "=== Checking Helm installation ==="

# Check if Helm is already installed
if command -v helm &> /dev/null; then
    echo "Helm is already installed: $(helm version --short)"
else
    echo "Installing Helm..."
    
    # Try multiple times with different methods in case of network issues
    MAX_ATTEMPTS=3
    ATTEMPT=1
    INSTALLED=false
    
    while [ $ATTEMPT -le $MAX_ATTEMPTS ] && [ "$INSTALLED" = "false" ]; do
        echo "Attempt $ATTEMPT of $MAX_ATTEMPTS to install Helm..."
        
        if [ $ATTEMPT -eq 1 ]; then
            # Method 1: Using the official script
            if curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3; then
                chmod 700 /tmp/get_helm.sh
                /tmp/get_helm.sh
                rm /tmp/get_helm.sh
                INSTALLED=true
            else
                echo "Official script download failed, trying alternative method..."
            fi
        elif [ $ATTEMPT -eq 2 ]; then
            # Method 2: Direct binary download
            HELM_VERSION=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | grep tag_name | cut -d '"' -f 4)
            if [ -z "$HELM_VERSION" ]; then
                HELM_VERSION="v3.12.3"  # Fallback version
            fi
            
            if curl -L -s -S --connect-timeout 30 --max-time 300 "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tar.gz; then
                mkdir -p /tmp/helm
                tar -zxf /tmp/helm.tar.gz -C /tmp/helm --strip-components=1
                sudo mv /tmp/helm/helm /usr/local/bin/helm
                rm -rf /tmp/helm /tmp/helm.tar.gz
                INSTALLED=true
            else
                echo "Direct download failed, trying alternative method..."
            fi
        elif [ $ATTEMPT -eq 3 ]; then
            # Method 3: Using snap
            if sudo snap install helm --classic; then
                INSTALLED=true
            else
                echo "Snap installation failed."
            fi
        fi
        
        ATTEMPT=$((ATTEMPT+1))
    done
    
    if [ "$INSTALLED" = "true" ] && command -v helm &> /dev/null; then
        echo "Helm installed successfully: $(helm version --short)"
    else
        echo "Failed to install Helm after $MAX_ATTEMPTS attempts."
        echo "Please install Helm manually."
    fi
fi

# Initialize Helm repositories
echo "Updating Helm repositories..."
helm repo update

echo "Helm setup completed."
