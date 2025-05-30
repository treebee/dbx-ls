# Databricks notebook source
# MAGIC %md
# MAGIC # Creating widgets and get values


# COMMAND ----------
from databricks.sdk.runtime import dbutils

dbutils.widgets.text("variable1", "")
dbutils.widgets.text("variable2", "")
dbutils.widgets.text("variable4", "")
dbutils.widgets.text("variable5", "")


# COMMAND ----------
variable1 = int(dbutils.widgets.get("variable1"))
variable2 = dbutils.widgets.get("variable2")
variable4 = int(dbutils.widgets.get("variable4") or 111)

# COMMAND ----------
