#!/usr/bin/env bash

repo_root=$1
VAULT_TOKEN_PATH=${VAULT_TOKEN_PATH:-"${HOME}/.vault-token"}

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
#vault_token_path=${12}
#submit_wdl_dir=${13}
#use_caas=${14}
#use_hmac=${15}

SCRIPT_DIR="${repo_root}/tests/integration_test"

bash ${SCRIPT_DIR}/integration_test.sh \
        "test" \
        "github" \
        "ra_update_to_caas_prod" \
        "github" \
        "rex-rhian-testing" \
        "github" \
        "master" \
        "github" \
        "master" \
        "$(tail -n+2 ${SCRIPT_DIR}/dss_staging_sub_ids.tsv | head -n1 | cut -f1)" \
        "$(tail -n+2 ${SCRIPT_DIR}/dss_staging_sub_ids.tsv | head -n1 | cut -f2)" \
        "${VAULT_TOKEN_PATH}" \
        "" \
        "true" \
        "true"
