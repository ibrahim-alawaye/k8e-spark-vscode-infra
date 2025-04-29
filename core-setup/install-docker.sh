#!/bin/bash

set -e

echo "=== Checking Docker installation ==="

# Check if Docker is already installed
if command -v docker &> /dev/null && docker --version &> /dev/null; then
    echo "Docker is already installed: $(docker --version)"
else
    echo "Installing Docker..."
    
    # Update package index
    sudo apt-get update

    # Install prerequisites
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg

    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

    # Set up the stable repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Update package index again
    sudo apt-get update

    # Install Docker Engine
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    
    echo "Docker installed successfully: $(docker --version)"
fi

# Check if current user is in docker group
if groups $USER | grep -q '\bdocker\b'; then
    echo "User $USER is already in the docker group."
else
    echo "Adding user $USER to the docker group..."
    sudo usermod -aG docker $USER
    echo "User added to docker group. You may need to log out and log back in for this to take effect."
fi

# Check if Docker Compose is already installed
if command -v docker-compose &> /dev/null && docker-compose --version &> /dev/null; then
    echo "Docker Compose is already installed: $(docker-compose --version)"
else
    echo "Installing Docker Compose..."
    
    # Try multiple times with different methods in case of network issues
    MAX_ATTEMPTS=3
    ATTEMPT=1
    INSTALLED=false
    
    while [ $ATTEMPT -le $MAX_ATTEMPTS ] && [ "$INSTALLED" = "false" ]; do
        echo "Attempt $ATTEMPT of $MAX_ATTEMPTS to install Docker Compose..."
        
        if [ $ATTEMPT -eq 1 ]; then
            # Method 1: Direct download
            if curl -L -s -S --connect-timeout 30 --max-time 300 "https://github.com/docker/compose/releases/download/v2.20.3/docker-compose-$(uname -s)-$(uname -m)" -o /tmp/docker-compose; then
                sudo mv /tmp/docker-compose /usr/local/bin/docker-compose
                sudo chmod +x /usr/local/bin/docker-compose
                INSTALLED=true
            else
                echo "Direct download failed, trying alternative method..."
            fi
        elif [ $ATTEMPT -eq 2 ]; then
            # Method 2: Using pip
            if command -v pip3 &> /dev/null || sudo apt-get install -y python3-pip; then
                sudo pip3 install docker-compose
                INSTALLED=true
            else
                echo "Pip installation failed, trying alternative method..."
            fi
        elif [ $ATTEMPT -eq 3 ]; then
            # Method 3: Using apt
            if sudo apt-get install -y docker-compose; then
                INSTALLED=true
            else
                echo "Apt installation failed."
            fi
        fi
        
        ATTEMPT=$((ATTEMPT+1))
    done
    
    if [ "$INSTALLED" = "true" ] && command -v docker-compose &> /dev/null; then
        echo "Docker Compose installed successfully: $(docker-compose --version)"
    else
        echo "Failed to install Docker Compose after $MAX_ATTEMPTS attempts."
        echo "Please install Docker Compose manually."
    fi
fi

echo "Docker setup completed."
