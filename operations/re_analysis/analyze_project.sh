#!/usr/bin/env bash
# This script streamlines triggering analysis of HCA datasets and has two main components:
# 1. Querying for the primary data bundles for a project based on the ${PROJECT_UUID}, DSS ${ENV} and ${WORKFLOW_NAME}
# 2. Sending notifications to ${ENV} Lira to process data bundles from step 1 with ${WORKFLOW_NAME}
#
# Note: If the project does not contain any data that matches the specified pipeline, the script will throw
# an error to prevent incorrect analysis.
#
# The script uses DRY_RUN=true by default, which allows you to see how many primary bundles were found for
# the specified project as well as which pipeline would be run. To run the analysis, set this parameter to false.
#
# If the workflows were previously analyzed and need to be re-run with a new pipeline version,
# set FORCE_REANALYSIS=true, otherwise the AUDR mechanism will consider these to be duplicate workflows
#
# Example Usage:
#   bash analyze_project.sh 12345 Test_SS2_Project AdapterSmartSeq2SingleCell prod true
#
# If a project contains data that matches more than one pipeline subscription:
#   bash analyze_project.sh 678910 Test_SS2_Optimus_Project AdapterSmartSeq2SingleCell prod true
#   bash analyze_project.sh 678910 Test_SS2_Optimus_Project AdapterOptimus prod true

PROJECT_UUID=${1}
PROJECT_SHORTNAME=${2}
WORKFLOW_NAME=${3}
ENV=${4}
DRY_RUN=${5:-true}
FORCE_REANALYSIS=${6:-false}

if [ ${ENV} == prod ]; then
    LIRA_URL=https://pipelines.data.humancellatlas.org
else
    LIRA_URL="https://pipelines.${ENV}.data.humancellatlas.org"
fi

if [ ${FORCE_REANALYSIS} == true ]; then
    FORCE_FLAG='--force'
else
    FORCE_FLAG='--no-force'
fi

BUNDLE_LIST_FILE="${PROJECT_UUID}_bundles.json"
LABELS='{"project_uuid":"'${PROJECT_UUID}'","project_shortname":"'${PROJECT_SHORTNAME}'"}'

# Query for ${PROJECT_UUID} primary bundles in the ${ENV} data store using the subscription query for ${WORKFLOW_NAME}
python query_bundles_by_project_id.py ${PROJECT_UUID} ${WORKFLOW_NAME} ${ENV} --output_file_path ${BUNDLE_LIST_FILE}

if [ ${DRY_RUN} == false ]; then
    printf "Running ${WORKFLOW_NAME} on ${PROJECT_SHORTNAME} dataset in ${ENV}"
    python notifier.py notify --lira_url ${LIRA_URL} --workflow_name ${WORKFLOW_NAME} --label ${LABELS} ${FORCE_FLAG} \
    batch --bundle_list_file ${BUNDLE_LIST_FILE} --sync
else
    printf "Running with DRY_RUN=true. Set DRY_RUN=false to run analysis workflows."
fi
