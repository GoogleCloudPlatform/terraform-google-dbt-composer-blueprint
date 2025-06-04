# Copyright 2025 The Reg Reporting Blueprint Authors

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
import logging
import os

from airflow.providers.cncf.kubernetes.operators.pod import (
    KubernetesPodOperator)
from airflow.providers.google.cloud.operators.cloud_run import (
    CloudRunExecuteJobOperator,
)
from kubernetes.client.models import V1VolumeMount, V1Volume, V1CSIVolumeSource
from google.cloud.run_v2.types import EnvVar

# Airflow environment variables (constant at startup)
#
# Available both in the environment and as variables.
PROJECT_ID = os.getenv('AIRFLOW_VAR_PROJECT_ID')
REGION = os.getenv('AIRFLOW_VAR_REGION')
BQ_LOCATION = os.getenv('AIRFLOW_VAR_BQ_LOCATION')
GCS_DOCS_BUCKET = os.getenv('AIRFLOW_VAR_GCS_DOCS_BUCKET')
WEBSERVER_BASE_URL = os.getenv('AIRFLOW__WEBSERVER__BASE_URL')


log = logging.getLogger(__name__)


class ComposerPodOperator(KubernetesPodOperator):

    def __init__(self,
                 # Mount GCS docs bucket into /gcs
                 mount_docs=False,
                 **kwargs):

        if mount_docs:

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
            kwargs['volume_mounts'].append(V1VolumeMount(
                name="docs-bucket",
                mount_path='/gcs',
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
        })

        # If capturing docs specify the DBT_LOG_PATH and DBT_TARGET_PATH
        # accordingly.
        #
        # The GCS_DOCS_BUCKET is for the dashboard to point to the bucket.
        #
        if capture_docs:
            env_vars.update({
                'DBT_ENV_CUSTOM_ENV_GCS_DOCS_BUCKET':
                    '{{ var.value.GCS_DOCS_BUCKET }}',
                'DBT_LOG_PATH': ('/gcs/{{ dag_run.dag_id }}/' +
                                 '{{ task.task_id }}/' +
                                 '{{ execution_date | ts }}/dbt/logs'),
                'DBT_TARGET_PATH': ('/gcs/{{ dag_run.dag_id }}/' +
                                    '{{ task.task_id }}/' +
                                    '{{ execution_date | ts }}/dbt/target'),
            })

        # Add generic Airflow environment variables
        env_vars.update({
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_BASE_URL':
                WEBSERVER_BASE_URL,
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_CTX_TASK_ID':
                '{{ task.task_id }}',
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_CTX_DAG_ID':
                '{{ dag_run.dag_id }}',
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_CTX_EXECUTION_DATE':
                '{{ execution_date | ts }}',
        })

        super().__init__(
            env_vars=env_vars,
            mount_docs=capture_docs,
            **kwargs)


class ComposerJobOperator(CloudRunExecuteJobOperator):
    """
    Override CloudRunExecuteJobOperator to enable templating
    the env overrides correctly.

    Pass it in as a dictionary and convert it to EnvVar pairs during
    execution.

    Note that this has a spurious warning which is captured in this
    issue here: https://github.com/apache/airflow/issues/41470
    """

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

    def execute(self, context):
        if self.overrides and 'container_overrides' in self.overrides:
            for container_override in self.overrides['container_overrides']:
                env = container_override.get('env', {})
                log.info("Rendered environment: %s", env)
                container_override['env'] = [
                    EnvVar(name=key, value=val)
                    for key, val in env.items()
                ]

        log.info("Cloud Run job: https://console.cloud.google.com/run/jobs/"
                 f"details/{self.region}/{self.job_name}/executions"
                 f"?project={self.project_id}")

        results = super().execute(context)

        job_id = results.get('latest_created_execution', {}).get('name', '')
        if job_id:
            logging_url = (
                "https://console.cloud.google.com/logs/query;" +
                "query=resource.type%20%3D%20%22cloud_run_job%22" +
                f"%0Aresource.labels.job_name%20%3D%20%22{self.job_name}%22" +
                "%0Alabels.%22run.googleapis.com%2Fexecution_name%22" +
                f"%20%3D%20%22{job_id}%22" +
                f"%0Aresource.labels.location%20%3D%20%22{self.region}%22" +
                "%0A;" +
                f"project={self.project_id}")
            log.info(f"Cloud Run execution {job_id}")
            log.info(f"Cloud Run logs: {logging_url}")

        return results


class DBTComposerJobOperator(ComposerJobOperator):
    def __init__(self,
                 job_name,
                 cmds,
                 env_vars={},
                 dbt_vars=None,
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
        })

        # If capturing docs specify the DBT_LOG_PATH and DBT_TARGET_PATH
        # accordingly.
        #
        # The GCS_DOCS_BUCKET should be the same as what's configured for the
        # Cloud Run Job.
        #
        if capture_docs:
            env_vars.update({
                'DBT_ENV_CUSTOM_ENV_GCS_DOCS_BUCKET':
                    '{{ var.value.GCS_DOCS_BUCKET }}',
                'DBT_LOG_PATH': ('/gcs/{{ dag_run.dag_id }}/' +
                                 '{{ task.task_id }}/' +
                                 '{{ execution_date | ts }}/dbt/logs'),
                'DBT_TARGET_PATH': ('/gcs/{{ dag_run.dag_id }}/' +
                                    '{{ task.task_id }}/' +
                                    '{{ execution_date | ts }}/dbt/target'),
            })

        # Add generic Airflow environment variables
        env_vars.update({
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_BASE_URL':
                WEBSERVER_BASE_URL,
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_CTX_TASK_ID':
                '{{ task.task_id }}',
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_CTX_DAG_ID':
                '{{ dag_run.dag_id }}',
            'DBT_ENV_CUSTOM_ENV_AIRFLOW_CTX_EXECUTION_DATE':
                '{{ execution_date | ts }}',
        })

        super().__init__(
            project_id=PROJECT_ID,
            region=REGION,
            job_name=job_name,
            overrides={
                'container_overrides': [{
                        'name': job_name,
                        'env': env_vars,
                        'args': cmds,
                }]
            },
            **kwargs
        )
