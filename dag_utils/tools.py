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

# Composer DAG to excute the Homeloan Delinquency workflow

import json
import os

from airflow.providers.cncf.kubernetes.operators.kubernetes_pod import (
    KubernetesPodOperator)

from kubernetes.client.models import V1VolumeMount, V1Volume, V1CSIVolumeSource

# Airflow environment variables (constant at startup)
#
# Available both in the environment and as variables.
PROJECT_ID = os.getenv('AIRFLOW_VAR_PROJECT_ID')
REGION = os.getenv('AIRFLOW_VAR_REGION')
BQ_LOCATION = os.getenv('AIRFLOW_VAR_BQ_LOCATION')
GCS_DOCS_BUCKET = os.getenv('AIRFLOW_VAR_GCS_DOCS_BUCKET')


class ComposerPodOperator(KubernetesPodOperator):

    def __init__(self,
                 # Directories to map into the DOCS gcs bucket
                 doc_dirs=[],
                 **kwargs):

        # NOTE: There is a limitation to the GCS Fuse that it
        # waits 30 seconds after a pod terminates.
        #
        # This delay is removed in the gcs-fuse-csi-driver but may not yet
        # be available in Composer and GKE Autopilot:
        # https://github.com/GoogleCloudPlatform/gcs-fuse-csi-driver/issues/91#issuecomment-1886185228
        if doc_dirs:

            # Initialize these values in kwargs
            kwargs.setdefault('annotations', {})
            kwargs.setdefault('volumes', [])
            kwargs.setdefault('volume_mounts', [])

            # Add in the required annotations
            kwargs['annotations'].update({
                "gke-gcsfuse/volumes": "true",
            })

            # Add in the docs bucket volume
            kwargs['volumes'].append(V1Volume(
                name="docs-bucket",
                csi=V1CSIVolumeSource(
                    driver="gcsfuse.csi.storage.gke.io",
                    read_only=False,
                    volume_attributes={
                        'bucketName': GCS_DOCS_BUCKET,
                        'mountOptions': ','.join([
                            'implicit-dirs',
                            'file-mode=0666',
                            'dir-mode=0777',
                        ]),
                    },
                )
            ))

            # Path in the docs bucket for the files
            sub_path = ('{{ dag_run.dag_id }}/{{ task.task_id }}' +
                        '/{{ execution_date | ts }}')

            # Add in the docs bucket volume
            for doc_dir in doc_dirs:
                kwargs['volume_mounts'].append(V1VolumeMount(
                    name="docs-bucket",
                    mount_path=doc_dir,
                    sub_path=sub_path + doc_dir,
                    read_only=False,
                ))

        super().__init__(

            # Always pull -- if image is updated, we need to use the latest
            image_pull_policy='Always',

            # See the following URL for why the config file needs to be set:
            # https://cloud.google.com/composer/docs/how-to/using/using-kubernetes-pod-operator#version-5-0-0
            config_file="/home/airflow/composer_kube_config",
            kubernetes_conn_id="kubernetes_default",

            # As per
            # https://cloud.google.com/composer/docs/composer-2/use-kubernetes-pod-operator,
            # use the composer-user-workloads namespace unless workload
            # identity is setup.
            namespace='composer-user-workloads',

            # Capture all of the logs
            get_logs=True,
            log_events_on_failure=True,
            is_delete_operator_pod=True,

            **kwargs)


class DBTComposerPodOperator(ComposerPodOperator):
    def __init__(self,
                 env_vars={},
                 dbt_vars=None,
                 doc_dirs=[],
                 capture_docs=True,
                 **kwargs):

        # Set DBT_VARS environment variable if necessary
        if dbt_vars:
            env_vars['DBT_VARS'] = json.dumps(dbt_vars)

        # Disable colours on output -- Airflow does not render it
        env_vars.setdefault('DBT_USE_COLORS', 'false')

        # Disable anonymous usage stats
        env_vars.setdefault('DBT_SEND_ANONYMOUS_USAGE_STATS', 'false')

        # Enable JSON logging (if desired)
        # env_vars.setdefault('DBT_LOG_FORMAT', 'json')

        # Add the general DBT environment variables
        env_vars.update({
            'DBT_ENV_CUSTOM_ENV_PROJECT_ID':
                '{{ var.value.PROJECT_ID }}',
            'DBT_ENV_CUSTOM_ENV_REGION':
                '{{ var.value.REGION }}',
            'DBT_ENV_CUSTOM_ENV_BQ_LOCATION':
                '{{ var.value.BQ_LOCATION }}',
            'DBT_ENV_CUSTOM_ENV_GCS_DOCS_BUCKET':
                '{{ var.value.GCS_DOCS_BUCKET }}',
        })

        # Add generic Airflow environment variables
        env_vars.update({
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_BASE_URL':
                os.getenv('AIRFLOW__WEBSERVER__BASE_URL'),
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_CTX_TASK_ID':
                '{{ task.task_id }}',
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_CTX_DAG_ID':
                '{{ dag_run.dag_id }}',
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_CTX_EXECUTION_DATE':
                '{{ execution_date | ts }}',
        })

        if capture_docs:
            doc_dirs = doc_dirs + [
                '/dbt/target',
                '/dbt/logs',
            ]

        super().__init__(
            env_vars=env_vars,
            doc_dirs=doc_dirs,
            **kwargs)
