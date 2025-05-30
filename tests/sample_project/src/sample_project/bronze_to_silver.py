# Databricks notebook source
# MAGIC %md
# MAGIC # Creating widgets and get values


# COMMAND ----------
from databricks.sdk.runtime import dbutils

dbutils.widgets.text("table", "")
dbutils.widgets.text("target", "")
dbutils.widgets.text("missing", "")


# COMMAND ----------
source_table = int(dbutils.widgets.get("table"))
target_table = dbutils.widgets.get("target")
missing = int(dbutils.widgets.get("missing") or 111)

# COMMAND ----------
