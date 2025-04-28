#!/usr/bin/env python3
"""
Sample script to submit a Spark job to the Kubernetes-deployed Spark cluster.
"""

from pyspark.sql import SparkSession
import random
import sys

def create_spark_session():
    """Create a Spark session configured to connect to the Kubernetes Spark cluster."""
    spark = SparkSession.builder \
        .appName("SparkPi") \
        .master("spark://spark-cluster-master-svc:7077") \
        .config("spark.driver.host", "spark-vscode-server") \
        .config("spark.driver.port", "4040") \
        .getOrCreate()
    
    return spark

def calculate_pi(spark, partitions=10):
    """
    Calculate Pi using Monte Carlo method.
    
    Args:
        spark: SparkSession
        partitions: Number of partitions to use
        
    Returns:
        Approximation of Pi
    """
    def inside_circle(_):
        x = random.random() * 2 - 1
        y = random.random() * 2 - 1
        return 1 if x**2 + y**2 <= 1 else 0
    
    num_samples = 100000 * partitions
    
    count = spark.sparkContext.parallelize(range(num_samples), partitions) \
        .map(inside_circle) \
        .reduce(lambda a, b: a + b)
    
    pi_value = 4.0 * count / num_samples
    return pi_value

def main():
    """Main function to run the Spark job."""
    print("Initializing Spark session...")
    spark = create_spark_session()
    
    try:
        print("Spark session created successfully!")
        print(f"Spark version: {spark.version}")
        print(f"Spark master: {spark.sparkContext.master}")
        
        # Run the Pi calculation
        partitions = 10
        if len(sys.argv) > 1:
            partitions = int(sys.argv[1])
        
        print(f"Calculating Pi using {partitions} partitions...")
        pi = calculate_pi(spark, partitions)
        
        print(f"Pi is approximately {pi}")
        
    finally:
        # Stop the Spark session
        spark.stop()
        print("Spark session stopped.")

if __name__ == "__main__":
    main()