# Copyright 2023 Google LLC

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


import datetime
import os

from dag_utils.tools import DBTComposerPodOperator
from airflow.models import Param
from airflow.decorators import dag

# Pull repo from the environment
REPO = os.getenv('AIRFLOW_VAR_REPO')


#
# Main dag
#
@dag(
    schedule_interval='@daily',
    catchup=False,
    start_date=datetime.datetime(2022, 1, 1),
    params={
        'tag': Param(
            default='latest',
            type='string',
        ),
        'repo': Param(
            default=REPO,
            type='string',
        ),
    },
)
def example_dbt_dag():

    # Launch the job, optionally parameterising it from different
    # repo and tag.
    DBTComposerPodOperator(
        name='example_dbt_job',
        task_id='example_dbt_job',
        image='{{ params.repo }}/example-dbt-job:{{ params.tag }}',
        cmds=[
            "/bin/bash",
            "-xc",
            "&&".join([
                "dbt run",
                # NOTE: --static requires version DBT 1.7+
                "dbt docs generate --static",
            ]),
        ],
        dbt_vars={
            "reporting_day": "{{ ds }}",
        },
    )

    # This is necessary if using DBT prior to 1.7.
    #
    # NOTE: The target prefix must have the task_id from the previous task
    # (example_dbt_job in this case)
    # generate_dbt_docs = dbt_static_docs(
    #     os.getenv('AIRFLOW_VAR_GCS_DOCS_BUCKET'),
    #     ('{{ dag_run.dag_id }}/' + 'example_dbt_job' +
    #      '/{{ execution_date | ts }}/dbt/target/'))


example_dbt_dag()
