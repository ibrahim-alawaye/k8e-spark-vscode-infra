#!/bin/bash

set -e

echo "=== Installing Apache Spark Cluster on Kubernetes ==="

# Function to check if a Kubernetes namespace exists
namespace_exists() {
    local namespace=$1
    kubectl get namespace $namespace &> /dev/null
    return $?
}

# Function to check if a Helm release exists
helm_release_exists() {
    local release=$1
    local namespace=$2
    helm status $release -n $namespace &> /dev/null
    return $?
}

# Function to check if a ConfigMap exists
configmap_exists() {
    local configmap=$1
    local namespace=$2
    kubectl get configmap $configmap -n $namespace &> /dev/null
    return $?
}

# Function to check if files have changed
files_changed() {
    local configmap=$1
    local namespace=$2
    local file1=$3
    local file2=$4
    
    # Create temporary files with current ConfigMap data
    local temp_dir=$(mktemp -d)
    
    if kubectl get configmap $configmap -n $namespace -o jsonpath="{.data['spark-defaults\.conf']}" > $temp_dir/spark-defaults.conf 2>/dev/null && \
       kubectl get configmap $configmap -n $namespace -o jsonpath="{.data['spark-env\.sh']}" > $temp_dir/spark-env.sh 2>/dev/null; then
        
        # Compare with new files
        if diff -q $temp_dir/spark-defaults.conf $file1 &>/dev/null && \
           diff -q $temp_dir/spark-env.sh $file2 &>/dev/null; then
            rm -rf $temp_dir
            return 1  # Files are the same
        fi
    fi
    
    rm -rf $temp_dir
    return 0  # Files are different or ConfigMap doesn't exist
}

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed or not in PATH"
    exit 1
fi

# Create namespace for Spark if it doesn't exist
if ! namespace_exists spark-cluster; then
    echo "Creating namespace spark-cluster..."
    kubectl create namespace spark-cluster
else
    echo "Namespace spark-cluster already exists."
fi

# Add Bitnami Helm repository if not already added
if ! helm repo list | grep -q "bitnami"; then
    echo "Adding Bitnami Helm repository..."
    helm repo add bitnami https://charts.bitnami.com/bitnami
else
    echo "Bitnami Helm repository already added."
fi

# Update Helm repositories
echo "Updating Helm repositories..."
helm repo update

# Check if config files exist
if [ ! -f "./config/spark-defaults.conf" ] || [ ! -f "./config/spark-env.sh" ]; then
    echo "Error: Configuration files are missing. Please ensure ./config/spark-defaults.conf and ./config/spark-env.sh exist."
    exit 1
fi

# Check if values file exists
if [ ! -f "./config/spark-values.yaml" ]; then
    echo "Error: Spark values file is missing. Please ensure ./config/spark-values.yaml exists."
    exit 1
fi

# Create or update ConfigMap for Spark configuration
if ! configmap_exists spark-config spark-cluster || files_changed spark-config spark-cluster "./config/spark-defaults.conf" "./config/spark-env.sh"; then
    echo "Creating/updating ConfigMap for Spark configuration..."
    kubectl create configmap spark-config -n spark-cluster \
        --from-file=spark-defaults.conf=./config/spark-defaults.conf \
        --from-file=spark-env.sh=./config/spark-env.sh \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "ConfigMap created/updated successfully."
else
    echo "ConfigMap spark-config is up to date, skipping update."
fi

# Install or upgrade Spark using Helm with custom values
if ! helm_release_exists spark-cluster spark-cluster; then
    echo "Installing Spark Helm chart..."
    helm install spark-cluster bitnami/spark \
        --namespace spark-cluster \
        --values ./config/spark-values.yaml \
        --timeout 10m
    echo "Spark Helm chart installed successfully."
else
    echo "Checking for Spark Helm chart updates..."
    # Get the current chart version
    CURRENT_VERSION=$(helm list -n spark-cluster -o json | jq -r '.[] | select(.name=="spark-cluster") | .chart' | cut -d- -f2)
    # Get the latest available version
    LATEST_VERSION=$(helm search repo bitnami/spark -o json | jq -r '.[0].version')
    
    if [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
        echo "Upgrading Spark Helm chart from version $CURRENT_VERSION to $LATEST_VERSION..."
    else
        echo "Applying any configuration changes to Spark Helm chart..."
    fi
    
    helm upgrade spark-cluster bitnami/spark \
        --namespace spark-cluster \
        --values ./config/spark-values.yaml \
        --timeout 10m
    echo "Spark Helm chart upgraded/updated successfully."
fi

# Wait for Spark deployment to be ready with timeout
echo "Waiting for Spark deployment to be ready (timeout: 5m)..."
if ! kubectl rollout status statefulset/spark-cluster-master -n spark-cluster --timeout=5m; then
    echo "Warning: Timeout waiting for Spark master to be ready."
else
    echo "Spark master is ready."
fi

if ! kubectl rollout status statefulset/spark-cluster-worker -n spark-cluster --timeout=5m; then
    echo "Warning: Timeout waiting for Spark workers to be ready."
else
    echo "Spark workers are ready."
fi

# Get Spark service details
SPARK_MASTER_URL=$(kubectl get svc spark-cluster -n spark-cluster -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "not-available")
SPARK_UI_PORT=$(kubectl get svc spark-cluster-ui -n spark-cluster -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "80")

echo "=== Apache Spark Cluster installation complete! ==="
echo "You can access the Spark UI at: http://<cluster-ip>:$SPARK_UI_PORT"
echo "Spark Master URL: spark://$SPARK_MASTER_URL:7077"
echo ""
echo "To submit a Spark job, use:"
echo "spark-submit --master spark://$SPARK_MASTER_URL:7077 --class org.apache.spark.examples.SparkPi /path/to/examples.jar 1000"
echo ""
echo "To check the status of your Spark cluster:"
echo "kubectl get all -n spark-cluster"
