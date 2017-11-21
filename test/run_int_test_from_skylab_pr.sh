#!/usr/bin/env bash

script_dir=$1
skylab_branch=$2

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

bash $script_dir/integration_test.sh \
        "dev" \
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
