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
  registry_url = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.composer-dbt-repo.name}"
}

# Enable APIs
# See https://github.com/terraform-google-modules/terraform-google-project-factory
# The modules/project_services
module "project_services" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "14.3.0"
  project_id                  = var.project_id
  disable_services_on_destroy = false
  disable_dependent_services  = false
  activate_apis = [
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
  ]
}

# Create artifact registry
resource "google_artifact_registry_repository" "composer-dbt-repo" {
  project       = module.project_services.project_id
  format        = "DOCKER"
  location      = var.region
  repository_id = "dbt-composer-repository"
  description   = "DBT and utility containers"
}

# Create DBT Composer setup
module "dbt_composer" {
  source       = "../.."
  project_id   = module.project_services.project_id
  region       = var.region
  gcs_location = var.gcs_location
  bq_location  = var.bq_location
  env_variables = {
    AIRFLOW_VAR_REPO : local.registry_url,
  }
}
