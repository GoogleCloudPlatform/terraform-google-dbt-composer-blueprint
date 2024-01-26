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

variable "project_id" {
  description = "The project ID to deploy to"
  type        = string
}

variable "region" {
  description = "The region for Cloud Composer"
  type        = string
}

variable "composer_version" {
  description = "Version of Cloud Composer"
  type        = string
  default     = "composer-2.5.4-airflow-2.6.3"
}

variable "env_variables" {
  type        = map(string)
  description = "Variables of the airflow environment."
  default     = {}
}

variable "gcs_location" {
  description = "The GCS location where the buckets will be created"
  type        = string
}

variable "bq_location" {
  description = "The BQ location where the datasets will be created"
  type        = string
}

variable "monitoring_dataset" {
  description = "Dataset for monitoring activity"
  type        = string
  default     = "monitoring"
}

variable "private_ip" {
  description = "Whether to use private connectivity for Composer"
  type        = bool
  default     = true
}

variable "goog_packaged_solution" {
  description = "Google packaged solution label"
  type        = string
  default     = "gcp-dbt-composer"
}

