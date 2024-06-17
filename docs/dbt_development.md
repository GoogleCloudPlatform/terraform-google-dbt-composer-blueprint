# Setup DBT in Cloud Shell

## Overview

This tutorial will setup Cloud Shell to be useful for basic DBT
development both from the command line and using Cloud Shell Editor.

## Install Python development tools

### Configure your PATH

Add $HOME/.local/bin to your path.

```sh
export PATH="$PATH:$HOME/.local/bin"
```

Now also add the export PATH command into your $HOME/.local/bin if it's not already there.
This ensures that in the future the path will always be available.

```sh
(grep -q '$HOME/.local/bin' $HOME/.profile) || (echo 'export PATH="$PATH:$HOME/.local/bin"' >> $HOME/.profile)
```

### Install Python tools

Open the Terminal and run pip install to install DBT, DBT BigQuery adapter, and sqlfluff tools.

```sh
pip3 install --user --upgrade dbt-core dbt-bigquery sqlfluff
```

### Test it out

Make sure DBT is in your path correctly.

```sh
dbt --version
```

## Install Cloud Shell Editor development tools

### Install Extensions

Install the DBT Power User extension in Cloud Shell Editor.

```sh
/google/devshell/editor/code-oss-for-cloud-shell/bin/codeoss-cloudshell --install-extension innoverio.vscode-dbt-power-user
```

Install the SQLfluff extension in Cloud Shell Editor.

```sh
/google/devshell/editor/code-oss-for-cloud-shell/bin/codeoss-cloudshell --install-extension RobertOstermann.vscode-sqlfluff
```

### Install Cloud Shell Editor example configuration

[Install](Install) the example configuration into the example DBT job.

```sh
docs/init_codeoss_settings.sh examples/dbt_job/dbt/.vscode/settings.json
```

Examine the sample configuration. SQLfluff should be configured.

```sh
cat examples/dbt_job/dbt/.vscode/settings.json
```

## Configure DBT profile

### Initialize the DBT profile

This will prompt you for the project and BigQuery location. This will control where
the data will be created.

```sh
docs/init_dbt_profiles.sh
```

Look at the install profile.

```sh
cat $HOME/.dbt/profiles.yml
```

## Explore the project

### Move to DBT project

```sh
cd examples/dbt_job/dbt
```

### Test out DBT

Note that this will request authorization (if not already provided) to access
BigQuery. This is a connectivity test.

```sh
dbt debug
```

This will connect to BigQuery, show versions of DBT, DBT BigQuery connector, and various other
self-tests. It should show success at the end of running.

## Start exploring Cloud Shell IDE

### Open up the DBT folder in in Cloud Shell IDE

This opens the Cloud Shell Editor in the current DBT directory.

```sh
cloudshell workspace .
```

Once open, open a few of the SQL files and explore the project. There are many
features there -- the DBT Power User extension and SQLfluff linting and formatting
are configured for this project.

### Close the terminal

Click X to close the terminal and continue with the IDE.
