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

SCRIPT_DIR=$1
ENVIRONMENT=$2
SERVICE=$3
BRANCH=$4
VAULT_TOKEN_PATH=$5

if [ "${SERVICE}" = "skylab" ];
then
    SUBMIT_WDL_DIR="submit_stub/"
else
    SUBMIT_WDL_DIR=""
fi

#Arguments to integration_test.sh:
#ENV=$1
#LIRA_MODE=$2
#LIRA_VERSION=$3
#PIPELINE_TOOLS_MODE=$4
#PIPELINE_TOOLS_VERSION=$5
#TENX_MODE=$6
#TENX_VERSION=$7
#SS2_MODE=$8
#SS2_VERSION=$9
#TENX_SUB_ID=${10}
#SS2_SUB_ID=${11}
#VAULT_TOKEN_PATH=${12}
#SUBMIT_WDL_DIR=${13}
#USE_CAAS=${14}
#USE_HMAC=${15}
#SUBMIT_AND_HOLD=${16}

bash "${SCRIPT_DIR}/integration_test.sh" \
        "${ENVIRONMENT}" \
        "github" \
        "${BRANCH}" \
        "github" \
        "${BRANCH}" \
        "github" \
        "${BRANCH}" \
        "github" \
        "${BRANCH}" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | head -n1 | cut -f1)" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | head -n1 | cut -f2)" \
        "${VAULT_TOKEN_PATH}" \
        "${SUBMIT_WDL_DIR}" \
        "true" \
        "false" \
        "true"
