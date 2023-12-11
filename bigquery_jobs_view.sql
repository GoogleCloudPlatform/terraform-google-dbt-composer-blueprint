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

  -- Pull out the InsertJob events after the job is DONE. This will contain
  -- the information about each job that is finished. Most of the information
  -- is contained in metadataJson.
  RawJobsData AS (
    SELECT
      PARSE_JSON(protopayload_auditlog.metadataJson) AS metadataJson,
      resource.labels.location,
      resource.labels.project_id,
      protopayload_auditlog.resourceName,
      protopayload_auditlog.authenticationInfo.principalEmail,
    FROM
      `${monitoring_dataset}.${audit_table}` d
    WHERE
      resource.type='bigquery_project' AND
      protopayload_auditlog.methodName='google.cloud.bigquery.v2.JobService.InsertJob' AND
      JSON_VALUE(protopayload_auditlog.metadataJson, "$.jobChange.after")='DONE'
  ),

  -- Extract from the metadataJson and resourceName important BigQuery
  -- attributes.
  ExtractedJobsData AS (
    SELECT
      STRUCT(
        project_id,
        location,
        principalEmail,
        REGEXP_EXTRACT(resourceName, "projects/[^/]*/jobs/(.*)") AS job_id,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobName") AS job_name,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobConfig.type") AS job_type,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobStatus.errorResult.code") AS error_code,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobStatus.errorResult.message") AS error_message,
        JSON_VALUE(metadataJson, "$.jobChange.reason") AS reason
      ) AS job,
      STRUCT(
        JSON_VALUE(metadataJson, "$.jobChange.job.jobConfig.queryConfig.writeDisposition") AS writeDisposition,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobConfig.queryConfig.statementType") AS statementType,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobConfig.queryConfig.createDisposition") AS create_disposition,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobConfig.queryConfig.destinationTable") AS destination_table,
        STRUCT(
          REGEXP_EXTRACT(JSON_VALUE(metadataJson, "$.jobChange.job.jobConfig.queryConfig.destinationTable"),
            r'projects/([^/]*)/') AS project,
          REGEXP_EXTRACT(JSON_VALUE(metadataJson, "$.jobChange.job.jobConfig.queryConfig.destinationTable"),
            r'projects/[^/]*/datasets/([^/]*)/') AS dataset,
          REGEXP_EXTRACT(JSON_VALUE(metadataJson, "$.jobChange.job.jobConfig.queryConfig.destinationTable"),
            r'projects/[^/]*/datasets/[^/]*/tables/(.*)') AS table
        ) AS destination_table_parts,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobConfig.queryConfig.priority") AS priority,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobConfig.queryConfig.query") AS query
      ) AS query,
      STRUCT(
        SAFE_CAST(JSON_VALUE(metadataJson, "$.jobChange.job.jobStats.createTime") AS TIMESTAMP) AS create_time,
        SAFE_CAST(JSON_VALUE(metadataJson, "$.jobChange.job.jobStats.endTime") AS TIMESTAMP) AS end_time,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobStats.queryStats.billingTier") AS billing_tier,
        IFNULL(
          SAFE_CAST(JSON_VALUE(metadataJson, "$.jobChange.job.jobStats.queryStats.outputRowCount") AS INT64),
           0) AS output_rows,
        JSON_VALUE(metadataJson, "$.jobChange.job.jobStats.queryStats.referencedTables") AS referenced_tables,
        IFNULL(
          SAFE_CAST(JSON_VALUE(metadataJson, "$.jobChange.job.jobStats.queryStats.totalBilledBytes") AS INT64),
         0) AS billed_bytes,
        IFNULL(
          SAFE_CAST(JSON_VALUE(metadataJson, "$.jobChange.job.jobStats.queryStats.totalProcessedBytes") AS INT64),
         0) AS processed_bytes,
        SAFE_CAST(JSON_VALUE(metadataJson, "$.jobChange.job.jobStats.startTime") AS TIMESTAMP) AS start_time,
        IFNULL(
          SAFE_CAST(JSON_VALUE(metadataJson, "$.jobChange.job.jobStats.totalSlotMs") AS INT64),
         0) AS slot_ms
      ) AS job_stats,
      JSON_QUERY(metadataJson, "$.jobChange.job.jobConfig.labels") AS labels
    FROM
      RawJobsData
  ),

  -- Extract DBT JSON structures from the query header and from
  -- DBT on run hook
  WithDBTPayload AS (
    SELECT
      *,
      REGEXP_EXTRACT(
        query.query,
        r'/* ({.*}) \*\/') AS dbt_hdr,
      REGEXP_EXTRACT(
        query.query,
        r'/* DBT ({.*}) \*\/') AS dbt_payload
    FROM
      ExtractedJobsData
  ),

  -- Extract from the dbt_payload and dbt_hdr JSON structures
  -- DBT-specific information (where available)
  WithDBTData AS (
    SELECT
      * EXCEPT (dbt_hdr),
      STRUCT(

        -- BigQuery deeplink
        CONCAT('https://console.cloud.google.com/bigquery',
          '?project=', job.project_id,
          '&j=bq:', job.location,
          ':', job.job_id,
          '&page=queryresults') AS bigquery_job,

        -- Destination table deeplink
        CONCAT('https://console.cloud.google.com/bigquery',
          '?project=', query.destination_table_parts.project,
          '&ws=!1m5!1m4!4m3!1s', query.destination_table_parts.project,
          '!2s', query.destination_table_parts.dataset,
          '!3s', query.destination_table_parts.table) AS destination_table

      ) AS links,
      STRUCT(
        JSON_VALUE(labels, "$.dbt_invocation_id") AS dbt_invocation_id,
        JSON_VALUE(dbt_hdr, "$.target_name") AS target_name,
        JSON_VALUE(dbt_hdr, "$.profile_name") AS profile_name,
        JSON_VALUE(dbt_hdr, "$.node_id") AS node_id,
        JSON_VALUE(dbt_hdr, "$.app") AS app,
        JSON_VALUE(dbt_hdr, "$.dbt_version") AS dbt_version
      ) AS dbt
    FROM
      WithDBTPayload
  )
SELECT
  *
FROM
  WithDBTData
