#!/usr/bin/env bash

script_dir=$1
service=$2
branch=$3
vault_token=$4

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

lira_branch=master
if [ $service = "lira" ]; then
    lira_branch=$branch
fi
pipeline_tools_branch=master
if [ $service = "pipeline-tools" ]; then
    pipeline_tools_branch=$branch
fi
skylab_branch=master
if [ $service = "skylab" ]; then
    skylab_branch=$branch
fi

bash $script_dir/render-ctmpls.sh "dev" $vault_token

bash $script_dir/integration_test.sh \
        "dev" \
        "github" \
        "$lira_branch" \
        "github" \
        "$pipeline_tools_branch" \
        "github" \
        "$skylab_branch" \
        "github" \
        "$skylab_branch" \
        "$script_dir/dev_config.json" \
        "$script_dir/lira-secrets.json"
