#!/usr/bin/env bash

script_dir=$1
service=$2
branch=$3
vault_token=$4

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

#Arguments to integration_test.sh:
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

bash $script_dir/integration_test.sh \
        "staging" \
        "github" \
        "$lira_branch" \
        "github" \
        "$pipeline_tools_branch" \
        "github" \
        "$skylab_branch" \
        "github" \
        "$skylab_branch" \
        $(tail -n+2 $script_dir/dss_staging_sub_ids.tsv | head -n1 | cut -f1) \
        $(tail -n+2 $script_dir/dss_staging_sub_ids.tsv | head -n1 | cut -f2) \
        "$vault_token"
