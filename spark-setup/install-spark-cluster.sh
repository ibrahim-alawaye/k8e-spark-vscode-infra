#!/bin/bash

set -e

echo "=== Installing Apache Spark Cluster on Kubernetes ==="

# Create namespace for Spark
kubectl create namespace spark-cluster || echo "Namespace spark-cluster already exists"

# Add Bitnami Helm repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

# Create ConfigMap for Spark configuration
echo "Creating ConfigMap for Spark configuration..."
kubectl create configmap spark-config -n spark-cluster --from-file=spark-defaults.conf=./config/spark-defaults.conf --from-file=spark-env.sh=./config/spark-env.sh || kubectl replace configmap spark-config -n spark-cluster --from-file=spark-defaults.conf=./config/spark-defaults.conf --from-file=spark-env.sh=./config/spark-env.sh

# Install Spark using Helm with custom values
echo "Installing Spark Helm chart..."
helm upgrade --install spark-cluster bitnami/spark \
  --namespace spark-cluster \
  --values ./config/spark-values.yaml \
  --timeout 10m

echo "Waiting for Spark deployment to be ready..."
kubectl rollout status statefulset/spark-cluster-master -n spark-cluster
kubectl rollout status statefulset/spark-cluster-worker -n spark-cluster

echo "=== Apache Spark Cluster installation complete! ==="
echo "You can access the Spark UI at: http://<cluster-ip>:80"
echo "To get the Spark Master URL, run: kubectl get svc spark-cluster -n spark-cluster"
echo ""
echo "To submit a Spark job, use:"
echo "spark-submit --master spark://\$(kubectl get svc spark-cluster -n spark-cluster -o jsonpath='{.spec.clusterIP}'):7077 --class org.apache.spark.examples.SparkPi /path/to/examples.jar 1000"