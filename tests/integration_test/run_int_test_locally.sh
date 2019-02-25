#!/usr/bin/env bash

SECONDARY_ANALYSIS_REPO_ROOT=$1
VAULT_TOKEN_PATH=${VAULT_TOKEN_PATH:-"${HOME}/.vault-token"}

#LIRA_ENVIRONMENT=${1}
#LIRA_MODE=${2}
#LIRA_VERSION=${3}
#LIRA_DIR=${4}
#SECONDARY_ANALYSIS_MODE=${5}
#SECONDARY_ANALYSIS_VERSION=${6}
#SECONDARY_ANALYSIS_DIR=${7}
#PIPELINE_TOOLS_MODE=${8}
#PIPELINE_TOOLS_VERSION=${9}
#PIPELINE_TOOLS_DIR=${10}
#TENX_MODE=${11}
#TENX_VERSION=${12}
#TENX_DIR=${13}
#SS2_MODE=${14}
#SS2_VERSION=${15}
#SS2_DIR=${16}
#TENX_SUB_ID=${17}
#SS2_SUB_ID=${18}
#VAULT_TOKEN_PATH=${19}
#SUBMIT_WDL_DIR=${20}
#USE_CAAS=${21}
#USE_HMAC=${22}
#SUBMIT_AND_HOLD=${23}
#REMOVE_TEMP_DIR=${24:-"true"}
#COLLECTION_NAME=${25:-"lira-${LIRA_ENVIRONMENT}"}

SCRIPT_DIR="${SECONDARY_ANALYSIS_REPO_ROOT}/tests/integration_test"

bash ${SCRIPT_DIR}/integration_test.sh \
        "test" \
        "github" \
        "master" \
        "" \
        "github" \
        "master" \
        "" \
        "github" \
        "master" \
        "" \
        "github" \
        "master" \
        "" \
        "github" \
        "master" \
        "" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | head -n1 | cut -f1)" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | head -n1 | cut -f2)" \
        "${VAULT_TOKEN_PATH}" \
        "" \
        "true" \
        "true" \
        "true"
