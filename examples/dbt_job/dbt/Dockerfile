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

FROM python:3.11

# Create user
ENV HOME /dbt/
RUN useradd -rm -d $HOME -s /bin/bash -u 1000 dbt
WORKDIR $HOME
USER dbt

# Add python bin dir on path
ENV PATH="${PATH}:/dbt/.local/bin"

# Install dependencies using require-hashes
RUN python3 -m ensurepip --upgrade
COPY --chown=dbt requirements.txt $HOME
RUN pip install --require-hashes -r requirements.txt

# Copy all other files to the image
COPY --chown=dbt . $HOME

# Default build and source references. This should be overridden on build,
# but if someone does local testing / development it will still work.
ARG BUILD_REF=dev
ARG BUILD_LOCATION=dev
ARG SOURCE_URL=dev
ARG SOURCE_REF=dev
ARG SOURCE_PATH=dev

# Set the environment variables for consumption in DBT
#
# Note environment variables start with DBT_ENV_CUSTOM_ENV so that
# it can be exposed conveniently within DBT.
ENV DBT_ENV_CUSTOM_ENV_BUILD_REF=${BUILD_REF}
ENV DBT_ENV_CUSTOM_ENV_BUILD_LOCATION=${BUILD_LOCATION}
ENV DBT_ENV_CUSTOM_ENV_SOURCE_URL=${SOURCE_URL}
ENV DBT_ENV_CUSTOM_ENV_SOURCE_REF=${SOURCE_REF}
ENV DBT_ENV_CUSTOM_ENV_SOURCE_PATH=${SOURCE_PATH}

# Setup default profiles for runtime
#
# It is expected during local development to use a different profile
ENV DBT_PROFILES_DIR $HOME/profiles

# Clean and initialize dependencies
RUN dbt clean
RUN dbt deps

