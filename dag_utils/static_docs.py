# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


from google.cloud import storage

from airflow.decorators import task

# Task to combine manifest.json, catalog.json, and index.html into
# a single file. This allows seeing the DBT documentation directly from
# GCS.
#
# This PR should make this unnecessary:
# https://github.com/dbt-labs/dbt-core/pull/8615
# It is due to be included in DBT 1.7


@task(task_id="dbt_static_docs")
def dbt_static_docs(bucket, path):
    storage_client = storage.Client()
    bucket = storage_client.bucket(bucket)

    # Open up all required GCS objects
    manifest = bucket.blob(path + 'manifest.json').open('r')
    catalog = bucket.blob(path + 'catalog.json').open('r')
    index = bucket.blob(path + 'index.html').open('r')
    static_index = bucket.blob(
        path + 'static_index.html'
    ).open('w', content_type='text/html; charset=utf-8')

    # Write the new static index
    with manifest, static_index, catalog, index:

        old_string = (
            'o=[i("manifest","manifest.json"+t),' +
            'i("catalog","catalog.json"+t)]')

        new_string = (
            "o=[{label: 'manifest', data: " + manifest.read() + "}," +
            "{label: 'catalog', data: " + catalog.read() + "}]")

        # Combine to a static_index.html
        static_index.write(index.read().replace(
            old_string, new_string))
