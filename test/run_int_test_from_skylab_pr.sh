#!/usr/bin/env bash

script_dir=$1
skylab_branch=$2
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

bash $script_dir/integration_test.sh \
        "dev" \
        "github" \
        "master" \
        "github" \
        "master" \
        "github" \
        "$skylab_branch" \
        "github" \
        "$skylab_branch" \
        "$vault_token"
