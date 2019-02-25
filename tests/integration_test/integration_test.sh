#!/usr/bin/env bash

# Runs an integration test for the secondary analysis service. Spins up a local instance of Lira,
# sends in notifications to launch workflows and waits for them to succeed or fail.

# This script carries out the following steps:
# 1. Clone mint-deployment
# 2. Clone Lira if needed
# 3. Get pipeline-tools version
# 4. Build or pull Lira image
# 5. Get pipeline versions
# 6. Create config.json
# 7. Start Lira
# 8. Send in notification
# 9. Poll Cromwell for completion
# 10. Stop Lira

# The following parameters are required. 
# Versions can be a branch name, tag, or commit hash
#
# LIRA_ENVIRONMENT
# The instance of Cromwell to use. When running from a PR, this will always be staging.
# When running locally, the developer can choose.
#
# LIRA_MODE and LIRA_VERSION
# The lira_mode param can be "local", "image" or "github".
# If "local" is specified, a local copy of the Lira code is used. In this case,
# LIRA_VERSION should be the local path to the repo.
# 
# If "image" is specified, this script will pull and run
# a particular version of the Lira docker image specified by lira_version.
# If LIRA_VERSION == "latest_released", then the script will scan the GitHub repo
# for the highest tagged version and try to pull an image with the same version.
# If LIRA_VERSION == "latest_deployed", then the script will use the latest
# deployed version in LIRA_ENVIRONMENT, specified in the deployment tsv. If lira_version is
# any other value, then it is assumed to be a docker image tag version and
# this script will attempt to pull that version.
#
# Note that in image mode, the Lira repo will still get cloned, but only to
# make use of the Lira config template file, in order to generate a config file
# to run Lira with.
#
# Running in "github" mode causes this script to clone the Lira repo and check
# out a specific branch specified by lira_version. If the branch does not exist,
# master will be used instead.
#
# PIPELINE_TOOLS_MODE and PIPELINE_TOOLS_VERSION
# These parameters determine where Lira will look for adapter WDLs.
# (pipeline-tools is also used as a Python library for Lira, but that version
# is controlled in Lira's Dockerfile).
# If PIPELINE_TOOLS_MODE == "local", then a local copy of the repo is used,
# with the path to the repo specified in PIPELINE_TOOLS_VERSION.
#
# If PIPELINE_TOOLS_MODE == "github", then the script configures Lira to read the
# wrapper WDLS from GitHub and to use branch PIPELINE_TOOLS_VERSION. If the branch
# does not exist, master will be used instead.
# If PIPELINE_TOOLS_VERSION is "latest_released", then the latest tagged release
# in GitHub will be used. If PIPELINE_TOOLS_VERSION is "latest_deployed" then
# the latest version from the deployment tsv is used.
#
# TENX_MODE and TENX_VERSION
# When TENX_MODE == "local", this script will configure lira to use the 10x wdl
# in a local directory specified by TENX_VERSION.
#
# When TENX_MODE == "github", this script will configure lira to use the 10x wdl
# in the skylab repo, with branch specified by TENX_VERSION. If the branch does
# not exist, master will be used instead.
# If TENX_VERSION == "latest_deployed", then this script will find the latest
# wdl version in the mint deployment TSV and configure lira to read that version
# from GitHub. If TENX_VERSION == "latest_released" then this script will use
# the latest tagged release in GitHub.
#
# SS2_MODE and SS2_VERSION
# The SS2_MODE and SS2_VERSION params work in the same way as TENX_MODE and
# TENX_VERSION.
#
# SS2_SUBSCRIPTION_ID
# Smart-seq2 subscription id
#
# TENX_SUBSCRIPTION_ID
# 10x subscription id
#
# VAULT_TOKEN_PATH
# Path to token file for vault auth
#
# SUBMIT_WDL_DIR
# Should be an empty string except when testing skylab, in which case we use
# "submit_stub/" so that we don't test submission, since it is not really
# necessary for skylab PRs.
#
# USE_CAAS
# Uses Cromwell-as-a-Service if true
#
# DOMAIN
# The domain of the deployed Lira instance, we hard-code it to use "localhost" here for testing
#
# USE_HMAC
# Uses hmac for authenticating notifications if true, otherwise uses query param token

DEBUG="false"

function set_debug {
    if [ ${DEBUG} == "true" ];
    then
        set -ex
    else
        set -e
    fi
}

function print_style {
    if [ "$1" == "info" ];
    then
        printf '\e[1;90m%-6s\e[m\n' "$2" # print gray
    elif [ "$1" == "error" ];
    then
        printf '\e[1;91m%-6s\e[m\n' "$2"  # print red
    elif [ "$1" == "success" ];
    then
        printf '\e[1;92m%-6s\e[m\n' "$2" # print green
    elif [ "$1" == "warn" ];
    then
        printf '\e[1;93m%-6s\e[m\n' "$2" # print yellow
    elif [ "$1" == "debug" ];
    then
        if [ "${DEBUG}" == "true" ];
        then
            printf '\e[1;90m%-6s\e[m\n' "$2" # print gray
        fi
    else
        printf "$1"
    fi

}

print_style "info" "Starting integration test"
print_style "info" "$(date +"%Y-%m-%d %H:%M:%S")"

LIRA_ENVIRONMENT=${1}
LIRA_MODE=${2}
LIRA_VERSION=${3}
LIRA_DIR=${4}
SECONDARY_ANALYSIS_MODE=${5}
SECONDARY_ANALYSIS_VERSION=${6}
SECONDARY_ANALYSIS_DIR=${7}
PIPELINE_TOOLS_MODE=${8}
PIPELINE_TOOLS_VERSION=${9}
PIPELINE_TOOLS_DIR=${10}
TENX_MODE=${11}
TENX_VERSION=${12}
TENX_DIR=${13}
SS2_MODE=${14}
SS2_VERSION=${15}
SS2_DIR=${16}
TENX_SUBSCRIPTION_ID=${17}
SS2_SUBSCRIPTION_ID=${18:-"placeholder_ss2_subscription_id"}
VAULT_TOKEN_PATH=${19}
SUBMIT_WDL_DIR=${20}
USE_CAAS=${21}
USE_HMAC=${22}
SUBMIT_AND_HOLD=${23}
COLLECTION_NAME=${24:-"lira-${LIRA_ENVIRONMENT}"}
REMOVE_TEMP_DIR=${25:-"true"}
DOMAIN="localhost"

WORK_DIR=$(pwd)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

GCLOUD_PROJECT=${GCLOUD_PROJECT:-"broad-dsde-mint-${LIRA_ENVIRONMENT}"} # other envs - broad-dsde-mint-test, broad-dsde-mint-staging, hca-dcp-pipelines-prod

CAAS_ENVIRONMENT="caas-prod"
LIRA_CONFIG_FILE="lira-config.json"

PIPELINE_TOOLS_PREFIX="https://raw.githubusercontent.com/HumanCellAtlas/pipeline-tools/${PIPELINE_TOOLS_VERSION}"
MAX_CROMWELL_RETRIES=${MAX_CROMWELL_RETRIES:-"1"}

# Cromwell URL - usually will be caas, but can be set to local environment
CROMWELL_URL=${CROMWELL_URL:-"https://cromwell.${CAAS_ENVIRONMENT}.broadinstitute.org/api/workflows/v1"}

# Derived Variables
CAAS_KEY_FILE="${CAAS_ENVIRONMENT}-key.json"

# Jumping through some hoops due to mismatch of names between our environments and the environments used by the other
# teams within the HCA - this sets up the correct name for the DSS URL and the INGEST URL
if [ ${LIRA_ENVIRONMENT} == "test" ];
then
    ENV="integration"
elif [ ${LIRA_ENVIRONMENT} == "int" ];
then
    ENV="integration"
elif [ ${LIRA_ENVIRONMENT} == "dev" ];
then
    ENV="integration"
else
    ENV="${LIRA_ENVIRONMENT}"
fi

function get_unused_port {
    PORT=$(gshuf -i 2000-65000 -n 1)
    QUIT=0

    while [ "${QUIT}" -ne 1 ]; do
      netstat -a | grep ${PORT} >> /dev/null
      if [ $? -gt 0 ]; then
        QUIT=1
        echo "${PORT}"
      else
        PORT=$(gshuf -i 2000-65000 -n 1)
      fi
    done
}

LIRA_DOCKER_CONTAINER_NAME="lira-$(date '+%Y-%m-%d-%H-%M-%S')"
LIRA_HOST_PORT=$(get_unused_port)

CAAS_KEY_PATH="secret/dsde/mint/${LIRA_ENVIRONMENT}/lira/${CAAS_ENVIRONMENT}-key.json"

if [ ${LIRA_ENVIRONMENT} == "prod" ];
then
    DSS_URL="https://dss.data.humancellatlas.org/v1"
    SCHEMA_URL="https://schema.humancellatlas.org/"
    INGEST_URL="https://api.ingest.data.humancellatlas.org/"
else
    DSS_URL="https://dss.${ENV}.data.humancellatlas.org/v1"
    SCHEMA_URL="http://schema.${ENV}.data.humancellatlas.org/"
    INGEST_URL="https://api.ingest.${ENV}.data.humancellatlas.org/"
fi

print_style "info" "getting version"
print_style "info" "$(date +"%Y-%m-%d %H:%M:%S")"
GCS_ROOT="gs://${GCLOUD_PROJECT}-cromwell-execution/caas-cromwell-executions"

function get_version {
    REPO=$1
    VERSION=$2
    BASE_URL="https://api.github.com/repos/HumanCellAtlas/${REPO}"
    BRANCHES_URL="${BASE_URL}/branches/${VERSION}"
    COMMITS_URL="${BASE_URL}/commits/${VERSION}"

    STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BRANCHES_URL}")

    if [ "${STATUS_CODE}" != "200" ]; then
        STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${COMMITS_URL}")
    fi

    if [ "${STATUS_CODE}" != "200" ]; then
        # 1>&2 prints message to stderr so it doesn't interfere with return value
        print_style "warn" "Couldn't find ${REPO} branch or commit ${VERSION}. Using master instead." 1>&2
        echo "master"
    else
        echo "${VERSION}"
    fi
}

function clone_secondary_analysis_repo {
    print_style "info" "Cloning secondary analysis deploy repo"
    git clone git@github.com:HumanCellAtlas/secondary-analysis-deploy.git

    export SECONDARY_ANALYSIS_DIR="${PWD}/secondary-analysis-deploy"
    cd "${SECONDARY_ANALYSIS_DIR}"

    if [ "${SECONDARY_ANALYSIS_VERSION}" == "latest_released" ];
    then
        print_style "info" "Determining latest release tag"
        export SECONDARY_ANALYSIS_VERSION="$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/lira)"
    else
        export SECONDARY_ANALYSIS_VERSION="$(get_version lira ${SECONDARY_ANALYSIS_VERSION})"
    fi

    print_style "info" "Checking out ${SECONDARY_ANALYSIS_VERSION}"
    git checkout ${SECONDARY_ANALYSIS_VERSION}
    cd "${WORK_DIR}/${TEMP_DIR}"
}

function clone_lira_repo {
    print_style "info" "Cloning lira repo"
    git clone git@github.com:HumanCellAtlas/lira.git

    export LIRA_DIR="${PWD}/lira"
    cd "${LIRA_DIR}"

    if [ "${LIRA_VERSION}" == "latest_released" ];
    then
        print_style "info" "Determining latest release tag"
        export LIRA_VERSION="$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/lira)"
    else
        export LIRA_VERSION="$(get_version lira ${LIRA_VERSION})"
    fi

    print_style "info" "Checking out ${LIRA_VERSION}"
    git checkout ${LIRA_VERSION}
    cd "${WORK_DIR}/${TEMP_DIR}"
}

function clone_pipeline_tools_repo {
    print_style "info" "Cloning pipeline-tools"
    git clone git@github.com:HumanCellAtlas/pipeline-tools.git

    export PIPELINE_TOOLS_DIR="${PWD}/pipeline-tools"
    cd "${PIPELINE_TOOLS_DIR}"

    if [ ${PIPELINE_TOOLS_VERSION} == "latest_released" ];
    then
        print_style "info" "Determining latest released version of pipeline-tools"
        export PIPELINE_TOOLS_VERSION=$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/pipeline-tools)
    else
        export PIPELINE_TOOLS_VERSION=$(get_version pipeline-tools ${PIPELINE_TOOLS_VERSION})
    fi

    print_style "info" "Checking out ${PIPELINE_TOOLS_VERSION}"
    git checkout ${PIPELINE_TOOLS_VERSION}
    cd "${WORK_DIR}/${TEMP_DIR}"
}

function build_lira {
    if [ ${LIRA_MODE} == "image" ];
    then
        if [ ${LIRA_VERSION} == "latest_released" ];
        then
            print_style "info" "Determining latest released version of Lira"
            export LIRA_IMAGE=$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/lira)
        elif [ ${LIRA_VERSION} == "latest_deployed" ];
        then
            print_style "info" "Determining latest deployed version of Lira"
            export LIRA_IMAGE=$(python ${SCRIPT_DIR}/current_deployed_version.py lira)
        else
            export LIRA_IMAGE=${LIRA_VERSION}
        fi

        docker pull quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE}

    elif [ "${LIRA_MODE}" == "local" ] || [ ${LIRA_MODE} == "github" ];
    then
        cd "${LIRA_DIR}"
        if [ "${LIRA_MODE}" == "local" ];
        then
            print_style "info" "Setting lira image version to 'LOCAL'"
            export LIRA_IMAGE=local

        elif [ "${LIRA_MODE}" == "github" ];
        then
            print_style "info" "Setting lira image version to ${LIRA_VERSION}"
            export LIRA_IMAGE=${LIRA_VERSION}
        fi

        docker build -t quay.io/humancellatlas/lira:${LIRA_IMAGE} .
    fi
    
    cd "${WORK_DIR}/${TEMP_DIR}"
}

function build_pipeline_tools {
# TODO: add conditional statement to use prebuilt pipeline-tools image as with lira?
    if [ "${PIPELINE_TOOLS_MODE}" == "local" ] || [ ${PIPELINE_TOOLS_MODE} == "github" ];
    then
        cd "${PIPELINE_TOOLS_DIR}"

        QUAY_USERNAME=$(docker run -i \
                                   --rm \
                                   -e VAULT_TOKEN="$(cat ${VAULT_TOKEN_PATH})" \
                                   broadinstitute/dsde-toolbox \
                                   vault read -field=username secret/dsde/mint/common/quay_robot)
        QUAY_TOKEN=$(docker run -i \
                                --rm \
                                -e VAULT_TOKEN="$(cat ${VAULT_TOKEN_PATH})" \
                                broadinstitute/dsde-toolbox \
                                vault read -field=password secret/dsde/mint/common/quay_robot)

        print_style "info" "Logging into quay.io using robot account ${QUAY_USERNAME}"
        docker login -u=${QUAY_USERNAME} -p=${QUAY_TOKEN} quay.io

        print_style "info" "Building pipeline-tools version \"${PIPELINE_TOOLS_VERSION}\" from dir: ${PIPELINE_TOOLS_DIR}"
        export PIPELINE_TOOLS_IMAGE="quay.io/humancellatlas/secondary-analysis-pipeline-tools:${PIPELINE_TOOLS_VERSION}"
        docker build -t ${PIPELINE_TOOLS_IMAGE} .

        print_style "info" "Pushing pipeline-tools image: ${PIPELINE_TOOLS_IMAGE}"
        docker push ${PIPELINE_TOOLS_IMAGE}
        cd "${WORK_DIR}/${TEMP_DIR}"
    fi
}

function get_10x_analysis_pipeline {
    if [ "${TENX_MODE}" == "github" ];
    then
        if [ "${TENX_VERSION}" == "latest_released" ];
        then
            print_style "info" "Determining latest released version of 10x pipeline"
            export TENX_VERSION="$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/skylab --tag_prefix 10x_v)"
        else
            export TENX_VERSION=$(get_version skylab ${TENX_VERSION})
        fi

        export TENX_PREFIX="https://raw.githubusercontent.com/HumanCellAtlas/skylab/${TENX_VERSION}"
        print_style "info" "Configuring Lira to use 10x wdl from skylab Github repo, version: ${TENX_VERSION}"
    elif [ ${TENX_MODE} == "local" ];
    then
        cd "${TENX_DIR}"
        export TENX_DIR=$(pwd)

        cd "${WORK_DIR}/${TEMP_DIR}"
        export TENX_PREFIX="/10x"

        print_style "info" "Using 10x wdl in dir: ${TENX_DIR}"
    fi

    export TENX_ANALYSIS_WDLS="[
                    \"${TENX_PREFIX}/pipelines/cellranger/cellranger.wdl\"
                ]"
    export TENX_OPTIONS_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/cellranger/options.json"
    export TENX_WDL_STATIC_INPUTS_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/cellranger/adapter_example_static.json"
    export TENX_WDL_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/cellranger/adapter.wdl"
    export TENX_WORKFLOW_NAME="Adapter10xCount"
}

function get_ss2_analysis_pipeline {
    if [ "${SS2_MODE}" == "github" ];
    then
        if [ "${SS2_VERSION}" == "latest_released" ];
        then
            print_style "info" "Determining latest released version of ss2 pipeline"
            export SS2_VERSION=$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/skylab --tag_prefix smartseq2_v)
        else
            export SS2_VERSION=$(get_version skylab ${SS2_VERSION})
        fi

        print_style "info" "Configuring Lira to use ss2 wdl from skylab GitHub repo, version: ${SS2_VERSION}"
        export SS2_PREFIX="https://raw.githubusercontent.com/HumanCellAtlas/skylab/${SS2_VERSION}"
    elif [ "${SS2_MODE}" == "local" ];
    then
        cd "${SS2_DIR}"
        export SS2_DIR=$(pwd)

        cd "${WORK_DIR}/${TEMP_DIR}"
        export SS2_PREFIX="/ss2"

        print_style "info" "Using ss2 wdl in dir: ${SS2_DIR}"
    fi

    export SS2_ANALYSIS_WDLS="[
                    \"${SS2_PREFIX}/pipelines/smartseq2_single_sample/SmartSeq2SingleSample.wdl\",
                    \"${SS2_PREFIX}/library/tasks/HISAT2.wdl\",
                    \"${SS2_PREFIX}/library/tasks/Picard.wdl\",
                    \"${SS2_PREFIX}/library/tasks/RSEM.wdl\",
                    \"${SS2_PREFIX}/library/tasks/GroupMetricsOutputs.wdl\",
                    \"${SS2_PREFIX}/library/tasks/ZarrUtils.wdl\"
                ]"
    export SS2_OPTIONS_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/ss2_single_sample/options.json"
    export SS2_WDL_STATIC_INPUTS_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/ss2_single_sample/adapter_example_static.json"
    export SS2_WDL_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/ss2_single_sample/adapter.wdl"
    export SS2_WORKFLOW_NAME="AdapterSmartSeq2SingleCell"
}

function stop_lira_on_error {
    print_style "error" "Stopping Lira"
    docker stop ${LIRA_DOCKER_CONTAINER_NAME}

    print_style "error" "Lira Log:"
    docker logs ${LIRA_DOCKER_CONTAINER_NAME}

    print_style "error" "Removing Lira"
    docker rm -v ${LIRA_DOCKER_CONTAINER_NAME}

    print_style "error" "Test failed!"
    exit 1
}

function start_lira {
    print_style "info" "Starting Lira docker image"
    if [ ${PIPELINE_TOOLS_MODE} == "local" ];
    then
        export MOUNT_PIPELINE_TOOLS="-v ${PIPELINE_TOOLS_DIR}:/pipeline-tools"
        print_style "info" "Mounting PIPELINE_TOOLS_DIR: ${PIPELINE_TOOLS_DIR}\n"
    fi
    if [ ${TENX_MODE} == "local" ];
    then
        export MOUNT_TENX="-v ${TENX_DIR}:/10x"
        print_style "info" "Mounting TENX_DIR: ${TENX_DIR}\n"
    fi
    if [ ${SS2_MODE} == "local" ];
    then
        export MOUNT_SS2="-v ${SS2_DIR}:/ss2"
        print_style "info" "Mounting SS2_DIR: ${SS2_DIR}\n"
    fi

    set +ex
    trap "stop_lira_on_error" ERR

    if [ ${USE_CAAS} ];
    then
        print_style "info" "docker run -d \
            -p ${LIRA_HOST_PORT}:8080 \
            -e lira_config=/etc/lira/lira-config.json \
            -e caas_key=/etc/lira/${CAAS_ENVIRONMENT}-key.json \
            -v ${CONFIG_DIR}/lira-config.json:/etc/lira/lira-config.json \
            -v ${CONFIG_DIR}/${CAAS_ENVIRONMENT}-key.json:/etc/lira/${CAAS_ENVIRONMENT}-key.json \
            --name=${LIRA_DOCKER_CONTAINER_NAME} \
            $(echo ${MOUNT_PIPELINE_TOOLS} | xargs) \
            $(echo ${MOUNT_TENX} | xargs) \
            $(echo ${MOUNT_SS2} | xargs) \
            quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE}"

        docker run -d \
            -p ${LIRA_HOST_PORT}:8080 \
            -e lira_config=/etc/lira/lira-config.json \
            -e caas_key=/etc/lira/${CAAS_ENVIRONMENT}-key.json \
            -v "${CONFIG_DIR}/lira-config.json":/etc/lira/lira-config.json \
            -v "${CONFIG_DIR}/${CAAS_ENVIRONMENT}-key.json":/etc/lira/${CAAS_ENVIRONMENT}-key.json \
            --name="${LIRA_DOCKER_CONTAINER_NAME}" \
            $(echo ${MOUNT_PIPELINE_TOOLS} | xargs) \
            $(echo ${MOUNT_TENX} | xargs) \
            $(echo ${MOUNT_SS2} | xargs) \
            quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE}
    else
        print_style "info" "docker run -d \
            -p ${LIRA_HOST_PORT}:8080 \
            -e lira_config=/etc/lira/lira-config.json \
            -v "${CONFIG_DIR}/lira-config.json":/etc/lira/lira-config.json \
            --name=${LIRA_DOCKER_CONTAINER_NAME} \
            $(echo ${MOUNT_PIPELINE_TOOLS} | xargs) \
            $(echo ${MOUNT_TENX} | xargs) \
            $(echo ${MOUNT_SS2} | xargs) \
            quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE}"

        docker run -d \
            -p ${LIRA_HOST_PORT}:8080 \
            -e lira_config=/etc/lira/lira-config.json \
            -v "${CONFIG_DIR}/lira-config.json":/etc/lira/lira-config.json \
            --name="${LIRA_DOCKER_CONTAINER_NAME}" \
            $(echo ${MOUNT_PIPELINE_TOOLS} | xargs) \
            $(echo ${MOUNT_TENX} | xargs) \
            $(echo ${MOUNT_SS2} | xargs) \
            quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE}
    fi

    print_style "info" "Waiting for Lira to finish start up"
    sleep 3

    n=$(docker ps -f "name=${LIRA_DOCKER_CONTAINER_NAME}" | wc -l)
    if [ ${n} -lt 1 ]; then
        print_style "error" "No container found with the name ${LIRA_DOCKER_CONTAINER_NAME}"
        exit 1
    elif [ ${n} -gt 2 ]; then
        print_style "error" "More than one container found with the name ${LIRA_DOCKER_CONTAINER_NAME}"
        exit 1
    fi

}

function send_ss2_notification {
    if [ "${USE_HMAC}" == "true" ];
    then
        print_style "info" "Getting hmac key"
        export HMAC_KEY=$(docker run -i --rm \
            -e VAULT_TOKEN="$(cat ${VAULT_TOKEN_PATH})" \
            broadinstitute/dsde-toolbox \
            vault read -field=current_key secret/dsde/mint/${LIRA_ENVIRONMENT}/lira/hmac_keys)
        export AUTH_PARAMS="--hmac_key ${HMAC_KEY} --hmac_key_id current_key"
    else
        print_style "info" "Getting notification token"
        export notification_token=$(docker run -i --rm \
            -e VAULT_TOKEN="$(cat ${VAULT_TOKEN_PATH})" \
            broadinstitute/dsde-toolbox \
            vault read -field=notification_token secret/dsde/mint/${LIRA_ENVIRONMENT}/lira/lira_secret)
        export AUTH_PARAMS="--query_param_token $notification_token"
    fi

    print_style "info" "Sending in SS2 notifications"
    # Uses the docker image built from Dockerfile next to this script
    export SS2_WORKFLOW_ID=$(docker run --rm -v ${SCRIPT_DIR}:/app \
                        -e LIRA_URL="http://lira:8080/notifications" \
                        -e NOTIFICATION=/app/ss2_notification_dss_${LIRA_ENVIRONMENT}.json \
                        --link ${LIRA_DOCKER_CONTAINER_NAME}:lira \
                        quay.io/humancellatlas/secondary-analysis-mintegration /app/send_notification.py \
                        $(echo "${AUTH_PARAMS}" | xargs))

    print_style "info" "SS2_WORKFLOW_ID: ${SS2_WORKFLOW_ID}"

    print_style "info" "Awaiting workflow completion"

    # Uses the docker image built from Dockerfile next to this script
    if [ "${USE_CAAS}" == "true" ];
    then
        docker run --rm -v "${SCRIPT_DIR}:/app" \
            -v "${CONFIG_DIR}/${CAAS_ENVIRONMENT}-key.json:/etc/lira/${CAAS_ENVIRONMENT}-key.json" \
            -e WORKFLOW_IDS="${SS2_WORKFLOW_ID}" \
            -e WORKFLOW_NAMES="SmartSeq2" \
            -e CROMWELL_URL="https://cromwell.${CAAS_ENVIRONMENT}.broadinstitute.org" \
            -e CAAS_KEY="/etc/lira/${CAAS_ENVIRONMENT}-key.json" \
            -e TIMEOUT_MINUTES=120 \
            -e PYTHONUNBUFFERED=0 \
            --link ${LIRA_DOCKER_CONTAINER_NAME}:${LIRA_DOCKER_CONTAINER_NAME} \
            quay.io/humancellatlas/secondary-analysis-mintegration \
            /app/await_workflow_completion.py

    else
        export CROMWELL_USER="$(docker run -i --rm \
                                           -e VAULT_TOKEN=$(cat ${VAULT_TOKEN_PATH}) \
                                           broadinstitute/dsde-toolbox \
                                           vault read -field=cromwell_user \
                                                      secret/dsde/mint/${LIRA_ENVIRONMENT}/common/htpasswd)"

        export CROMWELL_PASSWORD="$(docker run -i --rm \
                                              -e VAULT_TOKEN=$(cat ${VAULT_TOKEN_PATH}) \
                                              broadinstitute/dsde-toolbox \
                                              vault read -field=cromwell_password \
                                                         secret/dsde/mint/${LIRA_ENVIRONMENT}/common/htpasswd)"

        docker run --rm -v "${SCRIPT_DIR}:/app" \
                   -e WORKFLOW_IDS="${SS2_WORKFLOW_ID}" \
                   -e WORKFLOW_NAMES="SmartSeq2" \
                   -e CROMWELL_URL="https://cromwell.mint-${LIRA_ENVIRONMENT}.broadinstitute.org" \
                   -e CROMWELL_USER="${CROMWELL_USER}" \
                   -e CROMWELL_PASSWORD="${CROMWELL_PASSWORD}" \
                   -e TIMEOUT_MINUTES=120 \
                   -e PYTHONUNBUFFERED=0 \
                   --link ${LIRA_DOCKER_CONTAINER_NAME}:${LIRA_DOCKER_CONTAINER_NAME} \
                   quay.io/humancellatlas/secondary-analysis-mintegration \
                   /app/await_workflow_completion.py
    fi
}

function send_10x_notification {
    if [ "${USE_HMAC}" == "true" ];
    then
        print_style "info" "Getting hmac key"
        export HMAC_KEY=$(docker run -i --rm \
            -e VAULT_TOKEN="$(cat ${VAULT_TOKEN_PATH})" \
            broadinstitute/dsde-toolbox \
            vault read -field=current_key secret/dsde/mint/${LIRA_ENVIRONMENT}/lira/hmac_keys)
        export AUTH_PARAMS="--hmac_key ${HMAC_KEY} --hmac_key_id current_key"
    else
        print_style "info" "Getting notification token"
        export notification_token=$(docker run -i --rm \
            -e VAULT_TOKEN="$(cat ${VAULT_TOKEN_PATH})" \
            broadinstitute/dsde-toolbox \
            vault read -field=notification_token secret/dsde/mint/${LIRA_ENVIRONMENT}/lira/lira_secret)
        export AUTH_PARAMS="--query_param_token $notification_token"
    fi

    print_style "info" "Sending in 10X notifications"
    # Uses the docker image built from Dockerfile next to this script
    export TENX_WORKFLOW_ID=$(docker run --rm -v ${SCRIPT_DIR}:/app \
                        -e LIRA_URL="http://lira:8080/notifications" \
                        -e NOTIFICATION=/app/10x_notification_dss_${LIRA_ENVIRONMENT}.json \
                        --link ${LIRA_DOCKER_CONTAINER_NAME}:lira \
                        quay.io/humancellatlas/secondary-analysis-mintegration /app/send_notification.py \
                        $(echo "${AUTH_PARAMS}" | xargs))

    print_style "info" "TENX_WORKFLOW_ID: ${TENX_WORKFLOW_ID}"

    print_style "info" "Awaiting workflow completion"

    # Uses the docker image built from Dockerfile next to this script
    if [ "${USE_CAAS}" == "true" ];
    then
        docker run --rm -v "${SCRIPT_DIR}:/app" \
            -v "${CONFIG_DIR}/${CAAS_ENVIRONMENT}-key.json:/etc/lira/${CAAS_ENVIRONMENT}-key.json" \
            -e WORKFLOW_IDS="${TENX_WORKFLOW_ID}" \
            -e WORKFLOW_NAMES="10x" \
            -e CROMWELL_URL="https://cromwell.${CAAS_ENVIRONMENT}.broadinstitute.org" \
            -e CAAS_KEY="/etc/lira/${CAAS_ENVIRONMENT}-key.json" \
            -e TIMEOUT_MINUTES=120 \
            -e PYTHONUNBUFFERED=0 \
            --link ${LIRA_DOCKER_CONTAINER_NAME}:${LIRA_DOCKER_CONTAINER_NAME} \
            quay.io/humancellatlas/secondary-analysis-mintegration \
            /app/await_workflow_completion.py

    else
        export CROMWELL_USER="$(docker run -i --rm \
                                           -e VAULT_TOKEN=$(cat ${VAULT_TOKEN_PATH}) \
                                           broadinstitute/dsde-toolbox \
                                           vault read -field=cromwell_user \
                                                      secret/dsde/mint/${LIRA_ENVIRONMENT}/common/htpasswd)"

        export CROMWELL_PASSWORD="$(docker run -i --rm \
                                              -e VAULT_TOKEN=$(cat ${VAULT_TOKEN_PATH}) \
                                              broadinstitute/dsde-toolbox \
                                              vault read -field=cromwell_password \
                                                         secret/dsde/mint/${LIRA_ENVIRONMENT}/common/htpasswd)"

        docker run --rm -v "${SCRIPT_DIR}:/app" \
                   -e WORKFLOW_IDS="${TENX_WORKFLOW_ID}" \
                   -e WORKFLOW_NAMES="10x" \
                   -e CROMWELL_URL="https://cromwell.mint-${LIRA_ENVIRONMENT}.broadinstitute.org" \
                   -e CROMWELL_USER="${CROMWELL_USER}" \
                   -e CROMWELL_PASSWORD="${CROMWELL_PASSWORD}" \
                   -e TIMEOUT_MINUTES=120 \
                   -e PYTHONUNBUFFERED=0 \
                   --link ${LIRA_DOCKER_CONTAINER_NAME}:${LIRA_DOCKER_CONTAINER_NAME} \
                   quay.io/humancellatlas/secondary-analysis-mintegration \
                   /app/await_workflow_completion.py
    fi
}

# 0. Create temp directory for test repos

print_style "info" "Creating temp dir for test"
TEMP_DIR=$(mktemp -d mint_integration_test.XXXXXXXXXX)

cd "${WORK_DIR}/${TEMP_DIR}"


# 1. Define Location of Secondary Analysis (Image, Repo or Local)

if [ "${SECONDARY_ANALYSIS_MODE}" == "github" ] || [ ${SECONDARY_ANALYSIS_MODE} == "image" ];
then
    clone_secondary_analysis_repo
elif [ "${SECONDARY_ANALYSIS_MODE}" == "local" ];
then
    print_style "info" "Using secondary-analysis-deploy repo in dir: ${SECONDARY_ANALYSIS_DIR}"
fi

# Check that the Lira version is as expected

print_style "info" "SECONDARY_ANALYSIS_VERSION=${SECONDARY_ANALYSIS_VERSION}"
print_style "info" "SECONDARY_ANALYSIS_DIR=${SECONDARY_ANALYSIS_DIR}"

# 2. Define Location of Lira (Image, Repo or Local)

if [ "${LIRA_MODE}" == "github" ] || [ ${LIRA_MODE} == "image" ];
then
    clone_lira_repo
elif [ "${LIRA_MODE}" == "local" ];
then
    print_style "info" "Using Lira in dir: ${LIRA_DIR}"
fi

# Check that the Lira version is as expected

print_style "info" "LIRA_VERSION=${LIRA_VERSION}"
print_style "info" "LIRA_DIR=${LIRA_DIR}"


# 3. Define Location of pipeline-tools (Image, Repo or Local)

if [ ${PIPELINE_TOOLS_MODE} == "github" ] || [ ${PIPELINE_TOOLS_MODE} == "image" ];
then
    clone_pipeline_tools_repo
elif [ "${PIPELINE_TOOLS_MODE}" == "local" ];
then
    print_style "info" "Using pipeline-tools in dir: ${PIPELINE_TOOLS_DIR}"
fi

# Check that the pipeline-tools version is as expected

print_style "info" "PIPELINE_TOOLS_VERSION=${PIPELINE_TOOLS_VERSION}"
print_style "info" "PIPELINE_TOOLS_DIR=${PIPELINE_TOOLS_DIR}"


# 4. Define the pipeline tools prefix:

if [ ${PIPELINE_TOOLS_MODE} == "github" ] || [ ${PIPELINE_TOOLS_MODE} == "image" ];
then
    export PIPELINE_TOOLS_PREFIX="https://raw.githubusercontent.com/HumanCellAtlas/pipeline-tools/${PIPELINE_TOOLS_VERSION}"
    print_style "info" "Configuring Lira to use adapter wdls from pipeline-tools GitHub repo: ${PIPELINE_TOOLS_VERSION}"
elif [ "${PIPELINE_TOOLS_MODE}" == "local" ];
then
    export PIPELINE_TOOLS_PREFIX="/pipeline-tools"
    print_style "info" "Configuring Lira to use adapter wdls from pipeline-tools in dir: ${PIPELINE_TOOLS_DIR}"
fi

# Check that the pipeline-tools prefix is as expected

print_style "info" "PIPELINE_TOOLS_PREFIX=${PIPELINE_TOOLS_PREFIX}"


# 5. Define the submit wdl path

if [ -n "${SUBMIT_WDL_DIR}" ];
then
    export SUBMIT_WDL="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/${SUBMIT_WDL_DIR}/submit.wdl"
else
    export SUBMIT_WDL="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/submit.wdl"
fi

# Check that the submit wdl path is as expected

print_style "info" "PIPELINE_TOOLS_PREFIX=${PIPELINE_TOOLS_PREFIX}"


# 6. Build or Pull Lira Image

build_lira

# Check that the values are correct

print_style "info" "LIRA_IMAGE=${LIRA_IMAGE}"


# 7. Build or pull pipeline-tools image

build_pipeline_tools

# Check that the values are correct

print_style "info" "PIPELINE_TOOLS_IMAGE=${PIPELINE_TOOLS_IMAGE}"


# 8. Get analysis pipeline versions to use

get_10x_analysis_pipeline

get_ss2_analysis_pipeline


cd "${SECONDARY_ANALYSIS_DIR}"
export CONFIG_DIR="${SECONDARY_ANALYSIS_DIR}/config_files"


# 9. Create config.json file

print_style "debug" "LIRA_ENVIRONMENT=${LIRA_ENVIRONMENT}"
print_style "debug" "CROMWELL_URL=${CROMWELL_URL}"
print_style "debug" "USE_CAAS=${USE_CAAS}"
print_style "debug" "DOMAIN=${DOMAIN}"
print_style "debug" "SUBMIT_AND_HOLD=${SUBMIT_AND_HOLD}"
print_style "debug" "COLLECTION_NAME=${COLLECTION_NAME}"
print_style "debug" "GCLOUD_PROJECT=${GCLOUD_PROJECT}"
print_style "debug" "GCS_ROOT=${GCS_ROOT}"
print_style "debug" "LIRA_VERSION=${LIRA_VERSION}"
print_style "debug" "DSS_URL=${DSS_URL}"
print_style "debug" "SCHEMA_URL=${SCHEMA_URL}"
print_style "debug" "INGEST_URL=${INGEST_URL}"
print_style "debug" "USE_HMAC=${USE_HMAC}"
print_style "debug" "SUBMIT_WDL=${SUBMIT_WDL}"
print_style "debug" "MAX_CROMWELL_RETRIES=${MAX_CROMWELL_RETRIES}"
print_style "debug" "TENX_ANALYSIS_WDLS=${TENX_ANALYSIS_WDLS}"
print_style "debug" "TENX_OPTIONS_LINK=${TENX_OPTIONS_LINK}"
print_style "debug" "TENX_SUBSCRIPTION_ID=${TENX_SUBSCRIPTION_ID}"
print_style "debug" "TENX_WDL_STATIC_INPUTS_LINK=${TENX_WDL_STATIC_INPUTS_LINK}"
print_style "debug" "TENX_WDL_LINK=${TENX_WDL_LINK}"
print_style "debug" "TENX_WORKFLOW_NAME=${TENX_WORKFLOW_NAME}"
print_style "debug" "TENX_VERSION=${TENX_VERSION}"
print_style "debug" "SS2_ANALYSIS_WDLS=${SS2_ANALYSIS_WDLS}"
print_style "debug" "SS2_OPTIONS_LINK=${SS2_OPTIONS_LINK}"
print_style "debug" "SS2_SUBSCRIPTION_ID=${SS2_SUBSCRIPTION_ID}"
print_style "debug" "SS2_WDL_STATIC_INPUTS_LINK=${SS2_WDL_STATIC_INPUTS_LINK}"
print_style "debug" "SS2_WDL_LINK=${SS2_WDL_LINK}"
print_style "debug" "SS2_WORKFLOW_NAME=${SS2_WORKFLOW_NAME}"
print_style "debug" "SS2_VERSION=${SS2_VERSION}"
print_style "debug" "VAULT_TOKEN_PATH=${VAULT_TOKEN_PATH}"
print_style "debug" "SECONDARY_ANALYSIS_DIR=${SECONDARY_ANALYSIS_DIR}"
print_style "debug" "CTMPL FILE=${CONFIG_DIR}/${LIRA_CONFIG_FILE}.ctmpl"

docker run -i --rm \
              -e ENVIRONMENT="${LIRA_ENVIRONMENT}" \
              -e CROMWELL_URL="${CROMWELL_URL}" \
              -e USE_CAAS="${USE_CAAS}" \
              -e DOMAIN="${DOMAIN}" \
              -e SUBMIT_AND_HOLD="${SUBMIT_AND_HOLD}" \
              -e COLLECTION_NAME="${COLLECTION_NAME}" \
              -e GCLOUD_PROJECT="${GCLOUD_PROJECT}" \
              -e GCS_ROOT="${GCS_ROOT}" \
              -e LIRA_VERSION="${LIRA_VERSION}" \
              -e DSS_URL="${DSS_URL}" \
              -e SCHEMA_URL="${SCHEMA_URL}" \
              -e INGEST_URL="${INGEST_URL}" \
              -e USE_HMAC="${USE_HMAC}" \
              -e SUBMIT_WDL="${SUBMIT_WDL}" \
              -e MAX_CROMWELL_RETRIES="${MAX_CROMWELL_RETRIES}" \
              -e TENX_ANALYSIS_WDLS="${TENX_ANALYSIS_WDLS}" \
              -e TENX_OPTIONS_LINK="${TENX_OPTIONS_LINK}" \
              -e TENX_SUBSCRIPTION_ID="${TENX_SUBSCRIPTION_ID}" \
              -e TENX_WDL_STATIC_INPUTS_LINK="${TENX_WDL_STATIC_INPUTS_LINK}" \
              -e TENX_WDL_LINK="${TENX_WDL_LINK}" \
              -e TENX_WORKFLOW_NAME="${TENX_WORKFLOW_NAME}" \
              -e TENX_VERSION="${TENX_VERSION}" \
              -e SS2_ANALYSIS_WDLS="${SS2_ANALYSIS_WDLS}" \
              -e SS2_OPTIONS_LINK="${SS2_OPTIONS_LINK}" \
              -e SS2_SUBSCRIPTION_ID="${SS2_SUBSCRIPTION_ID}" \
              -e SS2_WDL_STATIC_INPUTS_LINK="${SS2_WDL_STATIC_INPUTS_LINK}" \
              -e SS2_WDL_LINK="${SS2_WDL_LINK}" \
              -e SS2_WORKFLOW_NAME="${SS2_WORKFLOW_NAME}" \
              -e SS2_VERSION="${SS2_VERSION}" \
              -v "${VAULT_TOKEN_PATH}":/root/.vault-token \
              -v "${CONFIG_DIR}":/working \
              --privileged \
              broadinstitute/dsde-toolbox:ra_rendering \
              /usr/local/bin/render-ctmpls.sh \
              -k "${LIRA_CONFIG_FILE}.ctmpl" || true

cat "${CONFIG_DIR}/${LIRA_CONFIG_FILE}"


# 10. Retrieve the caas-<<env>>-key.json file from vault

if [ ${USE_CAAS} ];
then
    print_style "info" "Retrieving caas service account key"
    docker run -i --rm \
                   -v "${VAULT_TOKEN_PATH}":/root/.vault-token \
                   -v "${PWD}":/working broadinstitute/dsde-toolbox:ra_rendering \
                   vault read -format=json "${CAAS_KEY_PATH}" | jq .data > "${CAAS_KEY_FILE}"

    mv "${CAAS_KEY_FILE}" "${CONFIG_DIR}"
fi


# 11. Start Lira

start_lira


# 12. Send in a notification

send_ss2_notification

send_10x_notification


# 13. Stop Lira
print_style "success" "Stopping Lira"
docker stop "${LIRA_DOCKER_CONTAINER_NAME}"

# 14. Cleanup - Remove the lira container

print_style "success" "Removing Lira"
docker rm -v "${LIRA_DOCKER_CONTAINER_NAME}"

# 15. Cleanup - Delete the temp directory
cd ${WORK_DIR}
if [ "${REMOVE_TEMP_DIR}" == "true" ];
then
    rm -r ${TEMP_DIR}
fi

print_style "success" "Test succeeded!"
