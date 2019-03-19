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

# LIRA_ENVIRONMENT=${1}
# LIRA_MODE=${2}
# LIRA_VERSION=${3}
# LIRA_DIR=${4}
# SECONDARY_ANALYSIS_MODE=${5}
# SECONDARY_ANALYSIS_VERSION=${6}
# SECONDARY_ANALYSIS_DIR=${7}
# PIPELINE_TOOLS_MODE=${8}
# PIPELINE_TOOLS_VERSION=${9}
# PIPELINE_TOOLS_DIR=${10}
# TENX_MODE=${11}
# TENX_VERSION=${12}
# TENX_DIR=${13}
# TENX_SUBSCRIPTION_ID=${14:-"placeholder_10x_subscription_id"}
# OPTIMUS_MODE=${15}
# OPTIMUS_VERSION=${16}
# OPTIMUS_DIR=${17}
# OPTIMUS_SUBSCRIPTION_ID=${18:-"placeholder_optimus_subscription_id"}
# SS2_MODE=${19}
# SS2_VERSION=${20}
# SS2_DIR=${21}
# SS2_SUBSCRIPTION_ID=${22:-"placeholder_ss2_subscription_id"}
# VAULT_TOKEN_PATH=${23}
# SUBMIT_WDL_DIR=${24}
# USE_CAAS=${25}
# USE_HMAC=${26}
# SUBMIT_AND_HOLD=${27}
# REMOVE_TEMP_DIR=${28:-"true"}
# COLLECTION_NAME=${29:-"lira-${LIRA_ENVIRONMENT}"}


bash "${SCRIPT_DIR}/integration_test.sh" \
        "${ENVIRONMENT}" \
        "github" \
        "${BRANCH}" \
        "" \
        "github" \
        "${BRANCH}" \
        "" \
        "github" \
        "${BRANCH}" \
        "" \
        "github" \
        "${BRANCH}" \
        "" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | head -n1 | cut -f1)" \
        "github" \
        "${BRANCH}" \
        "" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | head -n1 | cut -f2)" \
        "github" \
        "${BRANCH}" \
        "" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | head -n1 | cut -f3)" \
        "${VAULT_TOKEN_PATH}" \
        "${SUBMIT_WDL_DIR}" \
        "true" \
        "false" \
        "true"
