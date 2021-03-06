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
# ADAPTER_PIPELINES_MODE=${11}
# ADAPTER_PIPELINES_VERSION=${12}
# ADAPTER_PIPELINES_DIR=${13}
# TENX_MODE=${14}
# TENX_VERSION=${15}
# TENX_DIR=${16}
# TENX_SUBSCRIPTION_ID=${17:-"placeholder_10x_subscription_id"}
# OPTIMUS_MODE=${18}
# OPTIMUS_VERSION=${19}
# OPTIMUS_DIR=${20}
# OPTIMUS_SUBSCRIPTION_ID=${21:-"placeholder_optimus_subscription_id"}
# SS2_MODE=${22}
# SS2_VERSION=${23}
# SS2_DIR=${24}
# SS2_SUBSCRIPTION_ID=${25:-"placeholder_ss2_subscription_id"}
# VAULT_TOKEN_PATH=${26}
# SUBMIT_WDL_DIR=${27}
# USE_CAAS=${28}
# USE_HMAC=${29}
# SUBMIT_AND_HOLD=${30}
# REMOVE_TEMP_DIR=${31:-"true"}
# COLLECTION_NAME=${32:-"lira-${LIRA_ENVIRONMENT}"}


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
        "github" \
        "${BRANCH}" \
        "" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | cut -f1 -d " ")" \
        "github" \
        "${BRANCH}" \
        "" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | cut -f2 -d " ")" \
        "github" \
        "${BRANCH}" \
        "" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | cut -f3 -d " ")" \
        "${VAULT_TOKEN_PATH}" \
        "${SUBMIT_WDL_DIR}" \
        "true" \
        "false" \
        "true"
