#!/bin/bash

# Copyright 2023 Google LLC

# Licensed under the Apache License, Version 2.0 (the 'License');
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     https://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an 'AS IS' BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# Profiles to update
PROFILES_FILE="${HOME}/.dbt/profiles.yml"

# Create the profile directory
mkdir -p "$(dirname ${PROFILES_FILE})"

# Stop early if the DBT profile already exists -- do not overwrite
if [ -f "${PROFILES_FILE}" ]; then
  echo "DBT profile ${PROFILES_FILE} already exists. Exiting..."
  exit 0
fi

# Set the project if necessary
if [ "${PROJECT_ID}" == "" ]; then
  PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/project/project-id)
fi
if [[ "${PROJECT_ID}" == "" ]]; then
  PROJECT_ID="${GOOGLE_CLOUD_PROJECT}"
fi
if [[ "${PROJECT_ID}" == "" ]]; then
  read -p "Enter PROJECT_ID: " PROJECT_ID
fi

# Set BQ_LOCATION if not already set
if [ "${BQ_LOCATION}" == "" ]; then
  read -p "Enter BQ_LOCATION: " BQ_LOCATION
fi

# Create the profiles file
cat > "${PROFILES_FILE}" <<EOF
# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

config:
  partial_parse: false
  use_colors: true
  printer_width: 100
  send_anonymous_usage_stats: false

example_profile:
  target: prod

  outputs:
    prod:
      type: bigquery
      method: oauth
      project: "{{ env_var('DBT_ENV_CUSTOM_ENV_PROJECT_ID', '$PROJECT_ID') }}"
      location: "{{ env_var('DBT_ENV_CUSTOM_ENV_BQ_LOCATION', '$BQ_LOCATION') }}"
      dataset: dbt_composer_sample
      threads: 10
      timeout_seconds: 300
      priority: interactive
      retries: 1
EOF
