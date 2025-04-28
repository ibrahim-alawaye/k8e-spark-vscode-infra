#!/usr/bin/env bash

# This file is sourced when running various Spark programs.

# Options read when launching programs locally with
# ./bin/run-example or ./bin/spark-submit

# Options read by executors and drivers running inside the cluster
# - SPARK_WORKER_CORES, to set the number of cores to use on this machine
# - SPARK_WORKER_MEMORY, to set how much total memory workers have to give executors
# - SPARK_DRIVER_MEMORY, to set the driver memory
# - SPARK_EXECUTOR_MEMORY, to set the executor memory
# - SPARK_EXECUTOR_CORES, to set the number of cores used by executors

# Set Spark worker memory and cores
SPARK_WORKER_CORES=3
SPARK_WORKER_MEMORY=6g

# Set driver memory
SPARK_DRIVER_MEMORY=2g

# Set executor memory and cores
SPARK_EXECUTOR_MEMORY=4g
SPARK_EXECUTOR_CORES=2

# Set local directory for shuffle files
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

# Set Java options
SPARK_JAVA_OPTS="-XX:+UseG1GC -XX:+UseCompressedOops -XX:+PrintGCDetails -XX:+PrintGCTimeStamps -verbose:gc -Xloggc:/opt/bitnami/spark/logs/gc.log"

# Set Prometheus JMX exporter options
SPARK_DAEMON_JAVA_OPTS="-javaagent:/opt/bitnami/spark/jmx_prometheus_javaagent.jar=8080:/opt/bitnami/spark/conf/prometheus.yaml"