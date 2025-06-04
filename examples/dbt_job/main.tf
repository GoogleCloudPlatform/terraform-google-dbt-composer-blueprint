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
  version                     = "18.0.0"
  project_id                  = var.project_id
  disable_services_on_destroy = false
  disable_dependent_services  = false
  activate_apis = [
    "serviceusage.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "compute.googleapis.com",
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

# Default service account
data "google_compute_default_service_account" "default" {
  project = module.project_services.project_id
  depends_on = [module.project_services]
}

# Apply permissions to the service account (for Cloud Build)
resource "google_project_iam_member" "composer-dbt-iam" {
  project = module.project_services.project_id
  role    = "roles/storage.objectUser"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# Apply permissions to the service account (for Cloud Build)
resource "google_project_iam_member" "composer-dbt-iam-2" {
  project = module.project_services.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}

# Apply permissions to the service account (for Cloud Build)
resource "google_project_iam_member" "composer-dbt-iam-3" {
  project = module.project_services.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${data.google_compute_default_service_account.default.email}"
}


# Create DBT Composer setup
module "dbt_composer" {
  source           = "../.."
  project_id       = module.project_services.project_id
  region           = var.region
  gcs_location     = var.gcs_location
  bq_location      = var.bq_location
  composer_version = var.composer_version

  env_variables = {
    AIRFLOW_VAR_REPO : local.registry_url,
  }
}
