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


locals {
  env_name = "composer-dbt"
  project_apis = [
    "bigquery.googleapis.com",
    "composer.googleapis.com",
  ]
  project_api_identities = [{
    "api" : "composer.googleapis.com",
    "roles" : [
      "roles/composer.ServiceAgentV2Ext",
      "roles/composer.serviceAgent",
    ]
  }]
}

# Enable APIs
# See https://github.com/terraform-google-modules/terraform-google-project-factory
# The modules/project_services
module "project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "14.3.0"

  project_id                  = var.project_id
  disable_services_on_destroy = false
  disable_dependent_services  = false
  activate_apis               = local.project_apis
  activate_api_identities     = local.project_api_identities
}

module "gcs_docs_bucket" {
  source  = "terraform-google-modules/cloud-storage/google"
  version = "4.0.1"

  project_id       = module.project_services.project_id
  prefix           = module.project_services.project_id
  location         = var.gcs_location
  randomize_suffix = false

  # List of buckets to create
  names = [
    "docs",
  ]

  # Composer can write to docs GCS
  set_creator_roles = true
  creators = [
    "serviceAccount:${module.composer_service_account.email}",
  ]

  # Add bucket viewers (for target and logs directory) here
  bucket_viewers = {}
}
