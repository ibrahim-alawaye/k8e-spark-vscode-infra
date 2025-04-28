#!/bin/bash

# This script submits a Spark job to the Kubernetes-deployed Spark cluster

# Check if the Spark cluster is running
echo "Checking Spark cluster status..."
kubectl get pods -n spark-cluster

# Submit the Spark job
echo "Submitting Spark job..."
python3 submit_spark_job.py 20

# Alternative method using spark-submit
# spark-submit \
#   --master spark://spark-cluster-master-svc:7077 \
#   --deploy-mode client \
#   --conf spark.driver.host=spark-vscode-server \
#   --conf spark.driver.port=4040 \
#   submit_spark_job.py 20