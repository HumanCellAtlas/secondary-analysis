#!/usr/bin/env bash

script_dir=$1
skylab_branch=$2

#env=$1
#mint_deployment_dir=$2
#lira_mode=$3
#lira_version=$4
#pipeline_tools_mode=$5
#pipeline_tools_version=$6
#tenx_mode=$7
#tenx_version=$8
#ss2_mode=$9
#ss2_version=${10}
#env_config_json=${11}
#secrets_json=${12}

bash $script_dir/integration_test.sh \
        "dev" \
        "mint-deployment" \
        "github" \
        "ds_read_from_github_260" \
        "github" \
        "ds_move_wrapper_wdls_310" \
        "github" \
        "$skylab_branch" \
        "github" \
        "$skylab_branch" \
        "$script_dir/dev_config.json" \
        "$script_dir/dev_secrets.json"
