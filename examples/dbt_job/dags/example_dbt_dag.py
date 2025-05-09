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
import os # Keep import in case you use other env vars

from dag_utils.tools import DBTComposerPodOperator
from airflow.models import Param
from airflow.decorators import dag
from pendulum import datetime as pendulum_datetime # Using pendulum datetime for start_date is recommended

# The line below is kept, but its value will no longer be used
# as the *default* for the 'repo' param directly in the definition below.
# If you intend to use AIRFLOW_VAR_REPO elsewhere in your DAG logic, keep this.
# Otherwise, you could potentially remove it if 'repo' param is the only place it was used for default.
REPO_FROM_ENV = os.getenv('AIRFLOW_VAR_REPO')


#
# Main dag
#
@dag(
    dag_id='example_dbt_dag', # Explicitly defining dag_id is good practice
    schedule_interval='@daily',
    catchup=False,
    # Using pendulum datetime is recommended over standard datetime
    start_date=pendulum_datetime(2022, 1, 1, tz="UTC"), # Best practice to define timezone
    tags=['dbt', 'example'], # Adding tags helps with organization
    params={
        'tag': Param(
            default='latest',
            type='string',
            # description="Docker image tag for the dbt job", # Optional: Add description
        ),
        'repo': Param(
            # --- FIX APPLIED HERE ---
            # Provide a hardcoded fallback default string value directly.
            # This guarantees that the default is always a string, resolving the validation error.
            # Replace 'your_fallback_default_repo_here' with a meaningful default
            # (e.g., your standard repository path).
            default='us-central1-docker.pkg.dev/andresousa-pso-upskilling/dbt-repo',
            type='string',
            # description="Docker image repository for the dbt job", # Optional: Add description
        ),
    },
)



def example_dbt_dag():

    # Launch the job, optionally parameterising it from different
    # repo and tag.
    # The task still correctly uses {{ params.repo }} and {{ params.tag }}.
    # When the task runs, {{ params.repo }} will resolve to:
    # 1. The value provided when the DAG run was triggered (manual/API)
    # 2. OR, if no value was provided at trigger time, the 'default' value
    #    defined in the 'params' section above ('your_fallback_default_repo_here').
    #
    # Note: If you *do* set the AIRFLOW_VAR_REPO environment variable externally
    # in your Airflow environment, and you want *that* to be the default,
    # you would typically structure the Param default differently or ensure
    # the environment variable is always present.
    # The current rewrite prioritizes making the DAG file parseable by ensuring
    # a string default is always present *in the Param definition*.
    DBTComposerPodOperator(
        name='example_dbt_job',
        task_id='example_dbt_job',
        # This line correctly uses the parameter value dynamically
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


# Instantiate the DAG
example_dbt_dag()