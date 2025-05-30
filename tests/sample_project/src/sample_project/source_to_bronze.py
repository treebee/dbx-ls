# Databricks notebook source

# pylint: disable=undefined-variable
dbutils.widgets.text("table", "")
dbutils.widgets.text("target", "")
dbutils.widgets.text("connection", "")
dbutils.widgets.text("environment", "")
dbutils.widgets.text("missing", "")

# COMMAND ----------
source_table = dbutils.widgets.get("table")
target_table = dbutils.widgets.get("target")
connection = dbutils.widgets.get("connection")
missing = int(dbutils.widgets.get("missing") or 111)

# COMMAND ----------


spark = SparkSession.builder.getOrCreate()
source_df = spark.read.table(f"{connection}.{source_table}")
