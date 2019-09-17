#!/usr/bin/env bash

PROJECT_UUID=${1}
PROJECT_SHORTNAME=${2}
WORKFLOW_NAME=${3} #E.g. AdapterOptimus
ENV=${4}
DRY_RUN=${5:-"true"}

if [ ${ENV} == "prod" ];
then
    LIRA_URL="https://pipelines.data.humancellatlas.org"
else
    LIRA_URL="https://pipelines.${ENV}.data.humancellatlas.org"
fi

BUNDLE_LIST_FILE="${PROJECT_UUID}_bundles.json"
LABELS="{'project_uuid': '${PROJECT_UUID}', 'project_shortname': '${PROJECT_SHORTNAME}'}"

# Query for ${PROJECT_UUID} primary bundles in the ${ENV} data store using the subscription query for ${WORKFLOW_NAME}
python query_bundles_by_project_id.py ${PROJECT_UUID} ${WORKFLOW_NAME} ${ENV} --output_file_path ${BUNDLE_LIST_FILE}

if [ "${DRY_RUN}" == "false" ];
then
    printf "Running ${WORKFLOW_NAME} on ${PROJECT_SHORTNAME} dataset in ${ENV}"
    python notifier.py notify --lira_url ${LIRA_URL} --workflow_name ${WORKFLOW_NAME} --label ${LABELS} batch --bundle_list_file ${BUNDLE_LIST_FILE}
else
    printf "Running with DRY_RUN='true'. Set DRY_RUN=false to run analysis workflows."
fi
