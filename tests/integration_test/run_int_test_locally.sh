#!/usr/bin/env bash

LIRA_REPO_ROOT=$1
VAULT_TOKEN_PATH=${VAULT_TOKEN_PATH:-"${HOME}/.vault-token"}

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

SCRIPT_DIR="${LIRA_REPO_ROOT}/tests/integration_test"

bash ${SCRIPT_DIR}/integration_test.sh \
        "test" \
        "github" \
        "master" \
        "github" \
        "master" \
        "github" \
        "master" \
        "github" \
        "master" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | head -n1 | cut -f1)" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | head -n1 | cut -f2)" \
        "${VAULT_TOKEN_PATH}" \
        "" \
        "true" \
        "true"
