#!/usr/bin/env bash

# Launches the secondary analysis service integration test. This is intended to
# be run as a CI job that is triggered by GitHub notifications.
#
# The branch of the triggering PR will be passed into this script. This script
# assumes that identically named branches exist in all three repos used in the
# integration test, so passes in the same branch name for all of them. (The
# three repos are skylab, pipeline-tools, and lira.)
#
# This makes it easy to test changes that need to be coordinated across
# multiple repos: just make branches with the same name in the various repos,
# then open a pull request in one of them. The integration test will then
# test all the changes together.
#
# If the branch does not exist in a particular repo, then integration_test.sh
# will use master for that repo instead. Typically, changes are made in just
# one repo and we want to test them using the master branch of the other repos.

script_dir=$1
service=$2
branch=$3
vault_token=$4

if [ $service = "skylab" ]; then
    submit_wdl_dir="submit_stub/"
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
#submit_wdl_dir=${13}

bash $script_dir/integration_test.sh \
        "test" \
        "github" \
        "$branch" \
        "github" \
        "$branch" \
        "github" \
        "$branch" \
        "github" \
        "$branch" \
        $(tail -n+2 $script_dir/dss_staging_sub_ids.tsv | head -n1 | cut -f1) \
        $(tail -n+2 $script_dir/dss_staging_sub_ids.tsv | head -n1 | cut -f2) \
        "$vault_token" \
        "$submit_wdl_dir"
