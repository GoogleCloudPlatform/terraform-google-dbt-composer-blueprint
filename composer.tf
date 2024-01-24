# Copyright 2023 The Reg Reporting Blueprint Authors

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


locals {
  gcs_docs_bucket               = module.gcs_docs_bucket.buckets_map["docs"].name
  cluster_secondary_range_name  = "composer-subnet-cluster"
  services_secondary_range_name = "composer-subnet-services"
}

# Create a Cloud Composer specific service account
# See https://github.com/terraform-google-modules/terraform-google-service-accounts
module "composer_service_account" {
  source  = "terraform-google-modules/service-accounts/google"
  version = "4.2.1"

  project_id = module.project_services.project_id
  prefix     = local.env_name
  names = [
    "runner"
  ]
  project_roles = [
    "${module.project_services.project_id}=>roles/composer.worker",
    "${module.project_services.project_id}=>roles/iam.serviceAccountUser",
    "${module.project_services.project_id}=>roles/bigquery.dataEditor",
    "${module.project_services.project_id}=>roles/bigquery.jobUser",
  ]
}

# Create a new network and subnet
# See https://github.com/terraform-google-modules/terraform-google-network
module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "7.3.0"

  project_id   = module.project_services.project_id
  network_name = "${local.env_name}-network"
  routing_mode = "GLOBAL"

  subnets = [{
    subnet_name           = "composer-subnet"
    subnet_ip             = "10.10.10.0/24"
    subnet_region         = var.region
    subnet_private_access = "true"
  }]

  secondary_ranges = {
    composer-subnet = [
      {
        range_name    = local.cluster_secondary_range_name
        ip_cidr_range = "10.154.0.0/17"
      },
      {
        range_name    = local.services_secondary_range_name
        ip_cidr_range = "10.154.128.0/22"
      },
    ]
  }
}

# Create Composer 2 environment.
resource "google_composer_environment" "composer_env" {
  project = module.project_services.project_id
  name    = local.env_name
  region  = var.region

  labels = {
    goog-packaged-solution = var.goog_packaged_solution
  }

  # Tags and such can be filled in. Ignore changes after creation.
  lifecycle {
    ignore_changes = [
      # config["software_config"],
      # config["node_config"]
    ]
  }

  config {
    private_environment_config {
      connection_type = var.private_ip ? "PRIVATE_SERVICE_CONNECT" : null
      enable_private_endpoint = var.private_ip
    }
    software_config {
      image_version = var.composer_version
      env_variables = merge(tomap({
        AIRFLOW_VAR_PROJECT_ID      = module.project_services.project_id
        AIRFLOW_VAR_REGION          = var.region
        AIRFLOW_VAR_BQ_LOCATION     = var.bq_location
        AIRFLOW_VAR_GCS_DOCS_BUCKET = local.gcs_docs_bucket
        }),
        var.env_variables,
      )
    }
    environment_size = "ENVIRONMENT_SIZE_SMALL"
    node_config {
      network         = module.vpc.network_id
      subnetwork      = module.vpc.subnets["${var.region}/composer-subnet"].id
      service_account = module.composer_service_account.email
      ip_allocation_policy {
        cluster_secondary_range_name  = local.cluster_secondary_range_name
        services_secondary_range_name = local.services_secondary_range_name
      }
    }
  }
}

# NOTE: this is not the best way long term, see https://github.com/hashicorp/terraform-provider-google/issues/10488
# NOTE: this is preferred https://cloud.google.com/composer/docs/dag-cicd-integration-guide
# This details how to keep provider dependencies up to date:
# https://cloud.google.com/blog/topics/developers-practitioners/using-cloud-build-keep-airflow-operators-date-your-composer-environment
#
# Copy in initial DAG tools
resource "google_storage_bucket_object" "dag_helpers" {
  for_each = setunion(
    fileset(path.module, "dag_utils/**"),
    fileset(path.module, ".airflowignore"),
  )
  detect_md5hash = true
  source         = "${path.module}/${each.value}"
  name = format("%s/%s",
    regex("^gs://[^/]*/(.*)*", google_composer_environment.composer_env.config[0].dag_gcs_prefix)[0],
    each.value
  )
  bucket = regex("^gs://([^/]*)/", google_composer_environment.composer_env.config[0].dag_gcs_prefix)[0]
}


