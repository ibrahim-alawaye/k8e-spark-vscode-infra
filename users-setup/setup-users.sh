#!/bin/bash

set -e

echo "=== Setting up users and adding them to admin groups ==="

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found!"
    exit 1
fi

# Ensure required groups exist
echo "Checking if required groups exist..."
getent group $UBUNTU_ADMIN_GROUP > /dev/null || { echo "Error: $UBUNTU_ADMIN_GROUP group does not exist!"; exit 1; }
getent group $DOCKER_GROUP > /dev/null || { echo "Error: $DOCKER_GROUP group does not exist!"; exit 1; }
getent group $K8S_GROUP > /dev/null || { echo "Error: $K8S_GROUP group does not exist!"; exit 1; }

# Create users and add them to groups
IFS=',' read -ra USER_ARRAY <<< "$USERS"
for username in "${USER_ARRAY[@]}"; do
    username=$(echo "$username" | tr -d ' ')  # Remove any whitespace
    
    echo "Setting up user: $username"
    
    # Check if user already exists
    if id "$username" &>/dev/null; then
        echo "User $username already exists. Updating groups only."
    else
        # Create user with home directory
        useradd -m -s /bin/bash "$username"
        
        # Set default password
        echo "$username:$DEFAULT_PASSWORD" | chpasswd
        
        # Force password change on first login
        passwd -e "$username"
        
        echo "User $username created with default password (will be prompted to change on first login)"
    fi
    
    # Add user to Ubuntu admin group
    usermod -aG $UBUNTU_ADMIN_GROUP "$username"
    
    # Add user to Docker group
    usermod -aG $DOCKER_GROUP "$username"
    
    # Add user to Kubernetes (MicroK8s) group
    usermod -aG $K8S_GROUP "$username"
    
    echo "User $username added to $UBUNTU_ADMIN_GROUP, $DOCKER_GROUP, and $K8S_GROUP groups"
    
    # Create .kube directory for the user if it doesn't exist
    if [ ! -d "/home/$username/.kube" ]; then
        mkdir -p "/home/$username/.kube"
        chown -R "$username:$username" "/home/$username/.kube"
    fi
    
    # Add kubectl alias to user's .bashrc if it doesn't already exist
    if ! grep -q "alias kubectl=" "/home/$username/.bashrc"; then
        echo 'alias kubectl="microk8s kubectl"' >> "/home/$username/.bashrc"
    fi
    
    # Add KUBECONFIG export to user's .bashrc if it doesn't already exist
    if ! grep -q "export KUBECONFIG=" "/home/$username/.bashrc"; then
        echo 'export KUBECONFIG=~/.kube/config' >> "/home/$username/.bashrc"
    fi
    
    # Copy the Kubernetes config to the user's .kube directory
    microk8s config > "/home/$username/.kube/config"
    chown "$username:$username" "/home/$username/.kube/config"
    
    echo "Kubernetes configuration set up for $username"
done

echo "=== User setup complete! ==="
echo "Users have been created and added to the following groups:"
echo "- Ubuntu admin group: $UBUNTU_ADMIN_GROUP"
echo "- Docker group: $DOCKER_GROUP"
echo "- Kubernetes group: $K8S_GROUP"
echo ""
echo "Note: Users will be prompted to change their password on first login."
echo "Note: Users may need to log out and log back in for group changes to take effect."