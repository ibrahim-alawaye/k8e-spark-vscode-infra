#!/bin/bash

echo "=== Verifying user setup ==="

# Load environment variables
if [ -f .env ]; then
    source .env
else
    echo "Error: .env file not found!"
    exit 1
fi

# Check each user
IFS=',' read -ra USER_ARRAY <<< "$USERS"
for username in "${USER_ARRAY[@]}"; do
    username=$(echo "$username" | tr -d ' ')  # Remove any whitespace
    
    echo "Checking user: $username"
    
    # Check if user exists
    if id "$username" &>/dev/null; then
        echo "✓ User $username exists"
    else
        echo "✗ User $username does not exist!"
        continue
    fi
    
    # Check group memberships
    if groups "$username" | grep -q "\b$UBUNTU_ADMIN_GROUP\b"; then
        echo "✓ User $username is in $UBUNTU_ADMIN_GROUP group"
    else
        echo "✗ User $username is NOT in $UBUNTU_ADMIN_GROUP group!"
    fi
    
    if groups "$username" | grep -q "\b$DOCKER_GROUP\b"; then
        echo "✓ User $username is in $DOCKER_GROUP group"
    else
        echo "✗ User $username is NOT in $DOCKER_GROUP group!"
    fi
    
    if groups "$username" | grep -q "\b$K8S_GROUP\b"; then
        echo "✓ User $username is in $K8S_GROUP group"
    else
        echo "✗ User $username is NOT in $K8S_GROUP group!"
    fi
    
    # Check .kube directory
    if [ -d "/home/$username/.kube" ]; then
        echo "✓ User $username has .kube directory"
    else
        echo "✗ User $username does NOT have .kube directory!"
    fi
    
    # Check Kubernetes config
    if [ -f "/home/$username/.kube/config" ]; then
        echo "✓ User $username has Kubernetes config"
    else
        echo "✗ User $username does NOT have Kubernetes config!"
    fi
    
    # Check .bashrc for kubectl alias
    if grep -q "alias kubectl=" "/home/$username/.bashrc"; then
        echo "✓ User $username has kubectl alias in .bashrc"
    else
        echo "✗ User $username does NOT have kubectl alias in .bashrc!"
    fi
    
    echo ""
done

echo "=== Verification complete! ==="