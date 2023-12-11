-- Copyright 2023 Google LLC
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

WITH

  -- Group by dbt_invocation_id and extract any non-null dbt_payload --
  -- this gives us dbt_payload information which should be there once per DBT
  -- invocation (From the on run hook)
  SrcData AS (
    SELECT
      dbt.dbt_invocation_id,
      job.project_id,
      job.location,
      ARRAY_AGG(dbt_payload IGNORE NULLS LIMIT 1)[SAFE_OFFSET(0)] AS dbt_payload,
      MIN(job_stats.create_time) AS create_time,
      MAX(job_stats.end_time) AS end_time
    FROM
      `${monitoring_dataset}.${job_table}` j
    WHERE
      dbt.dbt_invocation_id IS NOT NULL
    GROUP BY
      1, 2, 3
  ),

  -- Extract key attributes from the dbt_payload. Note that any standard
  -- variables can be added to this extraction in the future.
  ExpandedValues AS (
    SELECT
      dbt_invocation_id,
      project_id,
      location,
      STRUCT(

        -- Airflow execution context (if launched from Airflow)
        STRUCT(
          JSON_VALUE(dbt_payload, "$.env.AIRFLOW_BASE_URL") AS base_url,
          JSON_VALUE(dbt_payload, "$.env.AIRFLOW_CTX_DAG_ID") AS dag_id,
          REPLACE(
            REPLACE(
              JSON_VALUE(dbt_payload, "$.env.AIRFLOW_CTX_EXECUTION_DATE"), ":", "%3A"),
            "+", "%2B") AS execution_date,
          JSON_VALUE(dbt_payload, "$.env.AIRFLOW_CTX_TASK_ID") AS task_id
        ) AS airflow,

        -- Standard airflow provided values (if launched from Airflow)
        STRUCT(
          JSON_VALUE(dbt_payload, "$.env.PROJECT_ID") AS project_id,
          JSON_VALUE(dbt_payload, "$.env.REGION") AS region,
          JSON_VALUE(dbt_payload, "$.env.BQ_LOCATION") AS bq_location,
          JSON_VALUE(dbt_payload, "$.env.GCS_DOCS_BUCKET") AS gcs_docs_bucket
        ) AS run_context,

        -- Build provided values (if built with example Dockerfile)
        STRUCT(
          JSON_VALUE(dbt_payload, "$.env.BUILD_LOCATION") AS build_location,
          JSON_VALUE(dbt_payload, "$.env.BUILD_REF") AS build_ref,
          JSON_VALUE(dbt_payload, "$.env.SOURCE_URL") AS source_url,
          JSON_VALUE(dbt_payload, "$.env.SOURCE_REF") AS source_ref,
          JSON_VALUE(dbt_payload, "$.env.SOURCE_PATH") AS source_path
        ) AS build,

        -- General parameters (for downstream extraction)
        JSON_VALUE(dbt_payload, "$.project") AS dbt_project,
        JSON_QUERY(dbt_payload, "$.env") AS env,
        JSON_QUERY(dbt_payload, "$.args") AS args
      ) AS dbt_invocation,

      -- Build some dbt_stats
      STRUCT(
        create_time,
        end_time,
        TIMESTAMP_DIFF(end_time, create_time, SECOND) AS elapsed_secs
      ) AS dbt_stats
    FROM
      SrcData
  ),

  -- Generate links from the data and join with the base BigQuery job information
  WithLinks AS (
    SELECT
      dbt_invocation_id,
      project_id,
      location,
      dbt_invocation,
      dbt_stats,

      -- DBT-specific links
      STRUCT(

        -- Airflow Dag link from execution
        CONCAT(dbt_invocation.airflow.base_url, "/graph?dag_id=", dbt_invocation.airflow.dag_id,
          "&execution_date=", dbt_invocation.airflow.execution_date) AS airflow_dag_link,

        -- Airflow Task Info link from execution
        CONCAT(dbt_invocation.airflow.base_url, "/log?dag_id=", dbt_invocation.airflow.dag_id,
          "&task_id=", dbt_invocation.airflow.task_id,
          "&execution_date=", dbt_invocation.airflow.execution_date) AS airflow_logs_link,

        -- Airflow Task Log link from execution
        CONCAT(dbt_invocation.airflow.base_url, "/task?dag_id=", dbt_invocation.airflow.dag_id,
          "&task_id=", dbt_invocation.airflow.task_id,
          "&execution_date=", dbt_invocation.airflow.execution_date) AS airflow_task_link,

        -- Browse the GCS bucket for this execution (target and logs)
        CONCAT("https://console.cloud.google.com/storage/browser/",
          dbt_invocation.run_context.gcs_docs_bucket, "/",
          dbt_invocation.airflow.dag_id, "/",
          dbt_invocation.airflow.task_id, "/",
          dbt_invocation.airflow.execution_date, "/dbt") AS dbt_archive,

        -- Provided generated documentation (if saved and converted to staic_index.html --
        -- see the example_dbt job)
        CONCAT("https://storage.cloud.google.com/",
          dbt_invocation.run_context.gcs_docs_bucket, "/",
          dbt_invocation.airflow.dag_id, "/",
          dbt_invocation.airflow.task_id, "/",
          dbt_invocation.airflow.execution_date,
          "/dbt/target/static_index.html") AS dbt_docs,

        -- Provided generated documentation, as above, but pulling out the specific model
        -- as per this job (if one provided)
        CONCAT("https://storage.cloud.google.com/",
          dbt_invocation.run_context.gcs_docs_bucket, "/",
          dbt_invocation.airflow.dag_id, "/",
          dbt_invocation.airflow.task_id, "/",
          dbt_invocation.airflow.execution_date,
          "/dbt/target/static_index.html",
          "#!/model/", dbt.node_id) AS dbt_model_docs,

        -- Cloud build link
        CONCAT("https://console.cloud.google.com/cloud-build/builds",
          ";region=", dbt_invocation.build.build_location,
          "/", dbt_invocation.build.build_ref) AS build_link,

        -- Source link if provided)
        CONCAT(dbt_invocation.build.source_url,
          dbt_invocation.build.source_ref,
          "/", dbt_invocation.build.source_path) AS src_link
      ) AS dbt_links,
      j.* EXCEPT (dbt_payload)
    FROM
      `${monitoring_dataset}.bigquery_jobs` j
      JOIN ExpandedValues ON (
         j.job.project_id=project_id
         AND j.job.location=location
         AND j.dbt.dbt_invocation_id=dbt_invocation_id
      )
  )
SELECT
  *
FROM
  WithLinks
