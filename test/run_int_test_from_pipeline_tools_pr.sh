#!/usr/bin/env bash

script_dir=$1
pipeline_tools_branch=$2
vault_token=$3

#env=$1
#lira_mode=$2
#lira_version=$3
#infra_mode=$4
#infra_version=$5
#tenx_mode=$6
#tenx_version=$7
#ss2_mode=$8
#ss2_version=$9
#env_config_json=${10}
#secrets_json=${11}

bash $script_dir/render-ctmpls.sh "dev" $vault_token

bash $script_dir/integration_test.sh \
        "dev" \
        "github" \
        "master" \
        "github" \
        "$pipeline_tools_branch" \
        "github" \
        "master" \
        "github" \
        "master" \
        "$script_dir/dev_config.json" \
        "$script_dir/lira_secrets.json"
