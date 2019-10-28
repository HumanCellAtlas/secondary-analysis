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
# DOMAIN="localhost"

SCRIPT_DIR="${SECONDARY_ANALYSIS_REPO_ROOT}/tests/integration_test"

# Note: we use `dev` as the default branch in secondary-analysis-deploy repo, not `master`
bash ${SCRIPT_DIR}/integration_test.sh \
        "integration" \
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
