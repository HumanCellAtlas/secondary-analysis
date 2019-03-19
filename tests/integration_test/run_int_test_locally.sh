#!/usr/bin/env bash

SECONDARY_ANALYSIS_REPO_ROOT=$1
VAULT_TOKEN_PATH=${VAULT_TOKEN_PATH:-"${HOME}/.vault-token"}

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
# DOMAIN="localhost"

SCRIPT_DIR="${SECONDARY_ANALYSIS_REPO_ROOT}/tests/integration_test"

# Note: we use `dev` as the default branch in secondary-analysis-deploy repo, not `master`
bash ${SCRIPT_DIR}/integration_test.sh \
        "test" \
        "github" \
        "master" \
        "" \
        "github" \
        "dev" \
        "" \
        "github" \
        "master" \
        "" \
        "github" \
        "master" \
        "" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | cut -f1 -d " ")" \
        "github" \
        "master" \
        "" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | cut -f2 -d " ")" \
        "github" \
        "master" \
        "" \
        "$(tail -n+2 ${SCRIPT_DIR}/mintegration_subscription_ids.tsv | cut -f3 -d " ")" \
        "${VAULT_TOKEN_PATH}" \
        "" \
        "true" \
        "true" \
        "true"
