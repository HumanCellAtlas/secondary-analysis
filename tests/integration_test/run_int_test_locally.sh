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
#tenx_sub_id=${10}
#ss2_sub_id=${11}
#vault_token=${12}
#submit_wdl_dir=${13}

script_dir=$repo_root/tests/integration_test

bash $script_dir/integration_test.sh \
        "test" \
        "github" \
        "master" \
        "github" \
        "master" \
        "github" \
        "master" \
        "github" \
        "master" \
        $(tail -n+2 $script_dir/dss_staging_sub_ids.tsv | head -n1 | cut -f1) \
        $(tail -n+2 $script_dir/dss_staging_sub_ids.tsv | head -n1 | cut -f2) \
        "$vault_token" \
        ""
