#!/usr/bin/env bash

repo_root=$1
vault_token=$(cat ~/.vault-token)

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

script_dir=$repo_root/test

bash $script_dir/render-ctmpls.sh "dev" $vault_token $repo_root

bash $script_dir/integration_test.sh \
        "dev" \
        "image" \
        "latest_released" \
        "github" \
        "ajc-create-ss2hisatrsem-adapter" \
        "github" \
        "latest_released" \
        "github" \
        "latest_released" \
        "$script_dir/dev_config.json" \
        "$script_dir/lira-secrets.json"
