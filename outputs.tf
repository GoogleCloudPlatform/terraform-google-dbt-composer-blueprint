/**
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */


output "airflow_uri" {
  description = "Airflow URI"
  value       = google_composer_environment.composer_env.config[0].airflow_uri
}

output "airflow_dag_gcs_prefix" {
  description = "Airflow GCS DAG prefix"
  value       = google_composer_environment.composer_env.config[0].dag_gcs_prefix
}

output "airflow_gke_cluster" {
  description = "Airflow GKE Cluster"
  value       = google_composer_environment.composer_env.config[0].gke_cluster
}

output "docs_gcs_bucket" {
  description = "Documentation bucket"
  value       = module.gcs_docs_bucket.buckets_map["docs"].name
}

output "lookerstudio_create_dashboard_url" {
  description = "Looker Studio template dashboard"
  # TODO: Fill out form with https://b.corp.google.com/issues?q=componentid:921724%20
  value      = "https://lookerstudio.google.com/reporting/create?c.reportId=1e0b060b-064a-4266-b115-e224da42689f&c.reportName=MyNewReport&ds.dbt_jobs.projectId=${var.project_id}&ds.dbt_jobs.billingProjectId=${var.project_id}&ds.dbt_jobs.type=TABLE&ds.dbt_jobs.datasetId=${var.monitoring_dataset}&ds.dbt_jobs.tableId=dbt_jobs"
}
