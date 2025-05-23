#!/usr/bin/env bash

# Set maximum worker resources
SPARK_WORKER_CORES=2
SPARK_WORKER_MEMORY=4g

# Set maximum driver memory
SPARK_DRIVER_MEMORY=2g

# Set maximum executor memory and cores
SPARK_EXECUTOR_MEMORY=4g
SPARK_EXECUTOR_CORES=2

# Set maximum total memory for all executors
SPARK_EXECUTOR_INSTANCES=4

# Set Spark local directory for shuffle files
SPARK_LOCAL_DIRS=/tmp/spark-local

# Set Spark logs directory
SPARK_LOG_DIR=/opt/bitnami/spark/logs

# Set Spark master recovery directory
SPARK_RECOVERY_DIR=/tmp/spark-recovery

# Set Spark event log directory
SPARK_EVENT_DIR=/tmp/spark-events

# Set Spark history server options
SPARK_HISTORY_OPTS="-Dspark.history.ui.port=18080 -Dspark.history.fs.logDirectory=${SPARK_EVENT_DIR} -Dspark.history.retainedApplications=50"

# Set Spark daemon memory
SPARK_DAEMON_MEMORY=1g

# Set Java options with memory constraints
SPARK_JAVA_OPTS="-XX:+UseG1GC -XX:+UseCompressedOops -XX:MaxHeapSize=4g -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -verbose:gc -Xloggc:/opt/bitnami/spark/logs/gc.log"

# Set Prometheus JMX exporter options
SPARK_DAEMON_JAVA_OPTS="-javaagent:/opt/bitnami/spark/jmx_prometheus_javaagent.jar=8080:/opt/bitnami/spark/conf/prometheus.yaml"
