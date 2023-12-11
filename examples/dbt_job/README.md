# DBT Job example

This example illustrates how to use Cloud Composer with a DBT container.

## Setup Infrastructure

To deploy this example do the following from a Linux command line:

1. Run `terraform init`.

2. Create a `terraform.tfvars` to provide values for `project_id`, `region`, `bq_location`, and `gcs_location`. Region is used for Cloud Composer and the artifact repository. BQ Location is used for the BigQuery storage location. GCS Location is used for the location of GCS buckets (multi-regional or single region).

3. Run `terraform apply`.

## Build and deploy the example DBT job

1. Export as environment variables the following outputs from terraform:
```
export PROJECT_ID=$(terraform output -raw project_id)
export REGISTRY_URL=$(terraform output -raw registry_url)
export AIRFLOW_DAG_GCS_PREFIX=$(terraform output -raw airflow_dag_gcs_prefix)

echo "Airflow is available at $(terraform output -raw airflow_uri)"
echo "Create your own dashboard is available at $(terraform output -raw lookerstudio_create_dashboard_url)"
```

2. Build and deploy the example DBT job:
```
gcloud builds submit --project $PROJECT_ID --substitutions "_SOURCE_URL=BaseSourceUrl,_REGISTRY_URL=${REGISTRY_URL},_AIRFLOW_DAG_GCS_PREFIX=${AIRFLOW_DAG_GCS_PREFIX}" .
```

Replace BaseSourceURL with the URL where your source is hosted if you wish to have a link back to source. For automated Cloud Build (linked to a merge), this will
ensure all containers have a link back to the original source code.

3. Visit the Airflow URL shown in step 1. The DBT dag deployed in step 2 should have already run and you can inspect its logs and status.

4. Visit the Looker Studio dashboard URL shown in step 1. This should enable you to save a new dashboard pointing at your newly created DBT Composer environment.

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| bq\_location | BigQuery dataset location | `string` | n/a | yes |
| gcs\_location | GCS location | `string` | n/a | yes |
| project\_id | The ID of the project in which to provision resources | `string` | n/a | yes |
| region | Region for composer and artifact repository | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| airflow\_dag\_gcs\_prefix | n/a |
| airflow\_uri | n/a |
| docs\_gcs\_bucket | n/a |
| lookerstudio\_create\_dashboard\_url | n/a |
| project\_id | n/a |
| registry\_url | Artefact registry for DBT containers |

<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
