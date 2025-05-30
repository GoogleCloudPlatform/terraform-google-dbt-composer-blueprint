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

from dag_utils.tools import DBTComposerJobOperator
from airflow.models import Param
from airflow.decorators import dag


#
# Run on Cloud Run Jobs.
#
@dag(
    schedule_interval=None,
    catchup=False,
    start_date=datetime.datetime(2022, 1, 1),
    params={
        'job_name': Param(
            default='example-dbt-run-job',
            type='string',
        ),
    },
)
def example_dbt_run_dag():

    # Launch the job, optionally parameterising it from different
    # job names.
    DBTComposerJobOperator(
        task_id='example_dbt_run_job',
        job_name='{{ params.job_name }}',
        capture_docs=True,
        cmds=[
            "/bin/bash",
            "-xc",
            "&&".join([
                "dbt run",
                "dbt docs generate --static",
            ]),
        ],
        dbt_vars={
            "reporting_day": "{{ ds }}",
        },
    )


example_dbt_run_dag()
