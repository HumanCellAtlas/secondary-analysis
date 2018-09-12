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
# USE_HMAC
# Uses hmac for authenticating notifications if true, otherwise uses query param token

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
    else
        printf "$1"
    fi

}

print_style "info" "Starting integration test"
print_style "info" "$(date +"%Y-%m-%d %H:%M:%S")"

set -e

LIRA_ENVIRONMENT=${1}
LIRA_MODE=${2}
LIRA_VERSION=${3}
PIPELINE_TOOLS_MODE=${4}
PIPELINE_TOOLS_VERSION=${5}
TENX_MODE=${6}
TENX_VERSION=${7}
SS2_MODE=${8}
SS2_VERSION=${9}
TENX_SUBSCRIPTION_ID=${10}
SS2_SUBSCRIPTION_ID=${11:-"placeholder_ss2_subscription_id"}
VAULT_TOKEN_PATH=${12}
SUBMIT_WDL_DIR=${13}
USE_CAAS=${14}
USE_HMAC=${15}
COLLECTION_NAME=${16:-"lira-${LIRA_ENVIRONMENT}"}

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
    PORT=$(shuf -i 2000-65000 -n 1)
    QUIT=0

    while [ "${QUIT}" -ne 1 ]; do
      netstat -a | grep ${PORT} >> /dev/null
      if [ $? -gt 0 ]; then
        QUIT=1
        echo "${PORT}"
      else
        PORT=$(shuf -i 2000-65000 -n 1)
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
    INGEST_URL="http://api.ingest.data.humancellatlas.org/"
else
    DSS_URL="https://dss.${ENV}.data.humancellatlas.org/v1"
    SCHEMA_URL="http://schema.${ENV}.data.humancellatlas.org/"
    INGEST_URL="http://api.ingest.${ENV}.data.humancellatlas.org/"
fi

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

# 1. Clone Lira if needed
if [ "${LIRA_MODE}" == "github" ] || [ ${LIRA_MODE} == "image" ];
then
  print_style "info" "Cloning lira"
  git clone git@github.com:HumanCellAtlas/lira.git

  LIRA_DIR="${PWD}/lira"
  cd "${LIRA_DIR}"

  if [ "${LIRA_VERSION}" == "latest_released" ];
  then
    print_style "info" "Determining latest release tag"
    LIRA_VERSION="$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/lira)"
  else
    LIRA_VERSION="$(get_version lira ${LIRA_VERSION})"
  fi

  print_style "info" "Checking out ${LIRA_VERSION}"

  git checkout ${LIRA_VERSION}
  cd "${WORK_DIR}"
elif [ "${LIRA_MODE}" == "local" ];
then
  print_style "info" "Using Lira in dir: ${LIRA_VERSION}"
  LIRA_DIR="${LIRA_VERSION}"
fi

# 2. Get pipeline-tools version
if [ ${PIPELINE_TOOLS_MODE} == "github" ];
then
  if [ ${PIPELINE_TOOLS_VERSION} == "latest_released" ];
  then
    print_style "info" "Determining latest released version of pipeline-tools"
    PIPELINE_TOOLS_VERSION=$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/pipeline-tools)
  else
    PIPELINE_TOOLS_VERSION=$(get_version pipeline-tools ${PIPELINE_TOOLS_VERSION})
  fi
  print_style "info" "Configuring Lira to use adapter wdls from pipeline-tools GitHub repo: ${PIPELINE_TOOLS_VERSION}"
  PIPELINE_TOOLS_PREFIX="https://raw.githubusercontent.com/HumanCellAtlas/pipeline-tools/${PIPELINE_TOOLS_VERSION}"
elif [ "${PIPELINE_TOOLS_MODE}" == "local" ];
then
  PIPELINE_TOOLS_PREFIX="/pipeline-tools"
  PIPELINE_TOOLS_DIR="${PIPELINE_TOOLS_VERSION}"
  # Get absolute path to PIPELINE_TOOLS_DIR, required to mount it into docker container later
  cd "${PIPELINE_TOOLS_DIR}"
  PIPELINE_TOOLS_DIR="$(pwd)"
  cd "${WORK_DIR}"
  print_style "info" "Configuring Lira to use adapter wdls in dir: ${PIPELINE_TOOLS_DIR}"
fi

if [ -n "${SUBMIT_WDL_DIR}" ];
then
    SUBMIT_WDL="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/${SUBMIT_WDL_DIR}/submit.wdl"
else
    SUBMIT_WDL="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/submit.wdl"
fi

# 3. Build or pull Lira image
if [ ${LIRA_MODE} == "image" ];
then
  if [ ${LIRA_VERSION} == "latest_released" ];
  then
    print_style "info" "Determining latest released version of Lira"
    LIRA_IMAGE_VERSION=$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/lira)

  elif [ ${LIRA_VERSION} == "latest_deployed" ];
  then
    print_style "info" "Determining latest deployed version of Lira"
    LIRA_IMAGE_VERSION=$(python ${SCRIPT_DIR}/current_deployed_version.py lira)

  else
    LIRA_IMAGE_VERSION=${LIRA_VERSION}
  fi

  docker pull quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE_VERSION}

elif [ "${LIRA_MODE}" == "local" ] || [ ${LIRA_MODE} == "github" ];
then
  cd "${LIRA_DIR}"
  if [ "${LIRA_MODE}" == "local" ];
  then
    LIRA_IMAGE_VERSION=local

  elif [ "${LIRA_MODE}" == "github" ];
  then
    LIRA_IMAGE_VERSION=${LIRA_VERSION}

  fi

  print_style "info" "Building Lira version \"${LIRA_IMAGE_VERSION}\" from dir: ${LIRA_DIR}"
  docker build -t quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE_VERSION} .
  cd "${WORK_DIR}"
fi

# 4. Get analysis pipeline versions to use
if [ ${TENX_MODE} == "github" ];
then
  if [ ${TENX_VERSION} == "latest_released" ];
  then
    print_style "info" "Determining latest released version of 10x pipeline"
    TENX_VERSION="$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/skylab --tag_prefix 10x_v)"
  else
    TENX_VERSION=$(get_version skylab ${TENX_VERSION})
  fi
  TENX_PREFIX="https://raw.githubusercontent.com/HumanCellAtlas/skylab/${TENX_VERSION}"
  print_style "info" "Configuring Lira to use 10x wdl from skylab Github repo, version: ${TENX_VERSION}"
elif [ ${TENX_MODE} == "local" ];
then
  TENX_DIR=${TENX_VERSION}
  cd ${TENX_DIR}
  TENX_DIR=$(pwd)
  cd ${WORK_DIR}
  TENX_PREFIX="/10x"
  print_style "info" "Using 10x wdl in dir: ${TENX_DIR}"
fi

if [ ${SS2_MODE} == "github" ];
then
  if [ ${SS2_VERSION} == "latest_released" ];
  then
    print_style "info" "Determining latest released version of ss2 pipeline"
    SS2_VERSION=$(python ${SCRIPT_DIR}/get_latest_release.py --repo HumanCellAtlas/skylab --tag_prefix smartseq2_v)
  else
    SS2_VERSION=$(get_version skylab ${SS2_VERSION})
  fi
  print_style "info" "Configuring Lira to use ss2 wdl from skylab GitHub repo, version: ${SS2_VERSION}"
  SS2_PREFIX="https://raw.githubusercontent.com/HumanCellAtlas/skylab/${SS2_VERSION}"
elif [ ${SS2_MODE} == "local" ];
then
  SS2_DIR=${SS2_VERSION}
  cd ${SS2_DIR}
  SS2_DIR=$(pwd)
  cd ${WORK_DIR}
  SS2_PREFIX="/ss2"
  print_style "info" "Using ss2 wdl in dir: ${SS2_DIR}"
fi


SS2_ANALYSIS_WDLS="[
                \"${SS2_PREFIX}/pipelines/smartseq2_single_sample/SmartSeq2SingleSample.wdl\",
                \"${SS2_PREFIX}/library/tasks/HISAT2.wdl\",
                \"${SS2_PREFIX}/library/tasks/Picard.wdl\",
                \"${SS2_PREFIX}/library/tasks/RSEM.wdl\"
            ]"
SS2_OPTIONS_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/ss2_single_sample/options.json"
SS2_WDL_STATIC_INPUTS_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/ss2_single_sample/adapter_example_static.json"
SS2_WDL_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/ss2_single_sample/adapter.wdl"
SS2_WORKFLOW_NAME="AdapterSmartSeq2SingleCell"

# TenX Variables
TENX_ANALYSIS_WDLS="[
                \"${TENX_PREFIX}/pipelines/10x/count/count.wdl\"
            ]"
TENX_OPTIONS_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/10x/options.json"
TENX_WDL_STATIC_INPUTS_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/10x/adapter_example_static.json"
TENX_WDL_LINK="${PIPELINE_TOOLS_PREFIX}/adapter_pipelines/10x/adapter.wdl"
TENX_WORKFLOW_NAME="Adapter10xCount"

# 5. Create config.json
print_style "info" "Creating Lira config"
print_style "info" "LIRA_ENVIRONMENT: ${LIRA_ENVIRONMENT}"
print_style "info" "CROMWELL_URL=${CROMWELL_URL}"
print_style "info" "USE_CAAS=${USE_CAAS}"
print_style "info" "COLLECTION_NAME=${COLLECTION_NAME}"
print_style "info" "GCLOUD_PROJECT=${GCLOUD_PROJECT}"
print_style "info" "GCS_ROOT=${GCS_ROOT}"
print_style "info" "LIRA_VERSION=${LIRA_VERSION}"
print_style "info" "DSS_URL=${DSS_URL}"
print_style "info" "SCHEMA_URL=${SCHEMA_URL}"
print_style "info" "INGEST_URL=${INGEST_URL}"
print_style "info" "USE_HMAC=${USE_HMAC}"
print_style "info" "SUBMIT_WDL=${SUBMIT_WDL}"
print_style "info" "MAX_CROMWELL_RETRIES=${MAX_CROMWELL_RETRIES}"
print_style "info" "TENX_ANALYSIS_WDLS=${TENX_ANALYSIS_WDLS}"
print_style "info" "TENX_OPTIONS_LINK=${TENX_OPTIONS_LINK}"
print_style "info" "TENX_SUBSCRIPTION_ID=${TENX_SUBSCRIPTION_ID}"
print_style "info" "TENX_WDL_STATIC_INPUTS_LINK=${TENX_WDL_STATIC_INPUTS_LINK}"
print_style "info" "TENX_WDL_LINK=${TENX_WDL_LINK}"
print_style "info" "TENX_WORKFLOW_NAME=${TENX_WORKFLOW_NAME}"
print_style "info" "TENX_VERSION=${TENX_VERSION}"
print_style "info" "SS2_ANALYSIS_WDLS=${SS2_ANALYSIS_WDLS}"
print_style "info" "SS2_OPTIONS_LINK=${SS2_OPTIONS_LINK}"
print_style "info" "SS2_SUBSCRIPTION_ID=${SS2_SUBSCRIPTION_ID}"
print_style "info" "SS2_WDL_STATIC_INPUTS_LINK=${SS2_WDL_STATIC_INPUTS_LINK}"
print_style "info" "SS2_WDL_LINK=${SS2_WDL_LINK}"
print_style "info" "SS2_WORKFLOW_NAME=${SS2_WORKFLOW_NAME}"
print_style "info" "SS2_VERSION=${SS2_VERSION}"
print_style "info" "VAULT_TOKEN_PATH=${VAULT_TOKEN_PATH}"
print_style "info" "PWD=${PWD}"
print_style "info" "LIRA_IMAGE_VERSION=${LIRA_IMAGE_VERSION}"
print_style "info" "LIRA_DOCKER_CONTAINER_NAME=${LIRA_DOCKER_CONTAINER_NAME}"
print_style "info" "LIRA_HOST_PORT=${LIRA_HOST_PORT}"

docker run -i --rm \
              -e LIRA_ENVIRONMENT="${LIRA_ENVIRONMENT}" \
              -e CROMWELL_URL="${CROMWELL_URL}" \
              -e USE_CAAS="${USE_CAAS}" \
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
              -v "${PWD}/lira/kubernetes":/working \
              broadinstitute/dsde-toolbox:ra_rendering \
              /usr/local/bin/render-ctmpls.sh \
              -k "/working/${LIRA_CONFIG_FILE}.ctmpl" || true

# 6. Retrieve the caas-<<env>>-key.json file from vault
if [ ${USE_CAAS} ];
then
    print_style "info" "Retrieving caas service account key"
    docker run -i --rm \
                   -v "${VAULT_TOKEN_PATH}":/root/.vault-token \
                   -v "${PWD}":/working broadinstitute/dsde-toolbox:ra_rendering \
                   vault read -format=json "${CAAS_KEY_PATH}" | jq .data > "${CAAS_KEY_FILE}"
     
    mv "${CAAS_KEY_FILE}" "${LIRA_DIR}/kubernetes/"
fi
               
# 7. Start Lira
print_style "info" "Starting Lira docker image"
if [ ${PIPELINE_TOOLS_MODE} == "local" ];
then
  MOUNT_PIPELINE_TOOLS="-v ${PIPELINE_TOOLS_DIR}:/pipeline-tools"
  print_style "info" "Mounting PIPELINE_TOOLS_DIR: ${PIPELINE_TOOLS_DIR}\n"
fi
if [ ${TENX_MODE} == "local" ];
then
  MOUNT_TENX="-v ${TENX_DIR}:/10x"
  print_style "info" "Mounting TENX_DIR: ${TENX_DIR}\n"
fi
if [ ${SS2_MODE} == "local" ];
then
  MOUNT_SS2="-v ${SS2_DIR}:/ss2"
  print_style "info" "Mounting SS2_DIR: ${SS2_DIR}\n"
fi

set +ex

function stop_lira_on_error {
  print_style "error" "Stopping Lira"
  docker stop ${LIRA_DOCKER_CONTAINER_NAME}
  print_style "error" "Removing Lira"
  docker rm -v ${LIRA_DOCKER_CONTAINER_NAME}
  print_style "error" "Test failed!"
  exit 1
}
trap "stop_lira_on_error" ERR

if [ ${USE_CAAS} ];
then
    print_style "info" "docker run -d \
        -p ${LIRA_HOST_PORT}:8080 \
        -e lira_config=/etc/lira/lira-config.json \
        -e caas_key=/etc/lira/kubernetes/${CAAS_ENVIRONMENT}-key.json \
        -v ${LIRA_DIR}/kubernetes/lira-config.json:/etc/lira/lira-config.json \
        -v ${LIRA_DIR}/kubernetes/${CAAS_ENVIRONMENT}-key.json:/etc/lira/${CAAS_ENVIRONMENT}-key.json \
        --name=${LIRA_DOCKER_CONTAINER_NAME} \
        $(echo ${MOUNT_PIPELINE_TOOLS} | xargs) \
        $(echo ${MOUNT_TENX} | xargs) \
        $(echo ${MOUNT_SS2} | xargs) \
        quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE_VERSION}"

    docker run -d \
        -p ${LIRA_HOST_PORT}:8080 \
        -e lira_config=/etc/lira/lira-config.json \
        -e caas_key=/etc/lira/${CAAS_ENVIRONMENT}-key.json \
        -v "${LIRA_DIR}/kubernetes/lira-config.json":/etc/lira/lira-config.json \
        -v "${LIRA_DIR}/kubernetes/${CAAS_ENVIRONMENT}-key.json":/etc/lira/${CAAS_ENVIRONMENT}-key.json \
        --name="${LIRA_DOCKER_CONTAINER_NAME}" \
        $(echo ${MOUNT_PIPELINE_TOOLS} | xargs) \
        $(echo ${MOUNT_TENX} | xargs) \
        $(echo ${MOUNT_SS2} | xargs) \
        quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE_VERSION}

else
    print_style "info" "docker run -d \
        -p ${LIRA_HOST_PORT}:8080 \
        -e lira_config=/etc/lira/lira-config.json \
        -v "${LIRA_DIR}/kubernetes/lira-config.json":/etc/lira/lira-config.json \
        --name=${LIRA_DOCKER_CONTAINER_NAME} \
        $(echo ${MOUNT_PIPELINE_TOOLS} | xargs) \
        $(echo ${MOUNT_TENX} | xargs) \
        $(echo ${MOUNT_SS2} | xargs) \
        quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE_VERSION}"

    docker run -d \
        -p ${LIRA_HOST_PORT}:8080 \
        -e lira_config=/etc/lira/lira-config.json \
        -v "${LIRA_DIR}/kubernetes/lira-config.json":/etc/lira/lira-config.json \
        --name="${LIRA_DOCKER_CONTAINER_NAME}" \
        $(echo ${MOUNT_PIPELINE_TOOLS} | xargs) \
        $(echo ${MOUNT_TENX} | xargs) \
        $(echo ${MOUNT_SS2} | xargs) \
        quay.io/humancellatlas/secondary-analysis-lira:${LIRA_IMAGE_VERSION}
fi

print_style "info" "Waiting for Lira to finish start up"
sleep 3

n=$(docker ps -f "name=${LIRA_DOCKER_CONTAINER_NAME}" | wc -l)
if [ ${n} -lt 1 ]; then
    print_style "error" "No container found with the name ${LIRA_DOCKER_CONTAINER_NAME}"
    exit 1
if [ ${n} -gt 1 ]; then
    print_style "error" "More than one container found with the name ${LIRA_DOCKER_CONTAINER_NAME}"
    exit 1
fi

# 8. Send in notifications

print_style "error" "GOT HERE !!!!!!!!!!!!"

if [ "${USE_HMAC}" == "true" ];
then
  print_style "info" "Getting hmac key"
  HMAC_KEY=$(docker run -i --rm \
        -e VAULT_TOKEN="$(cat ${VAULT_TOKEN_PATH})" \
        broadinstitute/dsde-toolbox \
        vault read -field=current_key secret/dsde/mint/${LIRA_ENVIRONMENT}/lira/hmac_keys)
  AUTH_PARAMS="--hmac_key $HMAC_KEY --hmac_key_id current_key"
else
  print_style "info" "Getting notification token"
  notification_token=$(docker run -i --rm \
        -e VAULT_TOKEN="$(cat ${VAULT_TOKEN_PATH})" \
        broadinstitute/dsde-toolbox \
        vault read -field=notification_token secret/dsde/mint/${LIRA_ENVIRONMENT}/lira/lira_secret)
  AUTH_PARAMS="--query_param_token $notification_token"
fi

print_style "info" "Sending in notifications"
# Uses the docker image built from Dockerfile next to this script
SS2_WORKFLOW_ID=$(docker run --rm -v ${SCRIPT_DIR}:/app \
                    -e LIRA_URL="http://lira:${LIRA_HOST_PORT}/notifications" \
                    -e NOTIFICATION=/app/ss2_notification_dss_${LIRA_ENVIRONMENT}.json \
                    --link ${LIRA_DOCKER_CONTAINER_NAME}:${LIRA_DOCKER_CONTAINER_NAME}\
                    quay.io/humancellatlas/secondary-analysis-mintegration /app/send_notification.py \
                    $(echo "${AUTH_PARAMS}" | xargs))

print_style "info" "SS2_WORKFLOW_ID: ${SS2_WORKFLOW_ID}"

# 9. Poll for completion
print_style "info" "Awaiting workflow completion"

# Uses the docker image built from Dockerfile next to this script
if [ ${USE_CAAS} == "true" ];
then
    docker run --rm -v ${SCRIPT_DIR}:/app \
        -v ${LIRA_DIR}/kubernetes/${CAAS_ENVIRONMENT}-key.json:/etc/lira/${CAAS_ENVIRONMENT}-key.json \
        -e WORKFLOW_IDS=${SS2_WORKFLOW_ID} \
        -e WORKFLOW_NAMES=ss2 \
        -e CROMWELL_URL=https://cromwell.${CAAS_ENVIRONMENT}.broadinstitute.org \
        -e CAAS_KEY=/etc/lira/${CAAS_ENVIRONMENT}-key.json \
        -e TIMEOUT_MINUTES=120 \
        -e PYTHONUNBUFFERED=0 \
        --link ${LIRA_DOCKER_CONTAINER_NAME}:${LIRA_DOCKER_CONTAINER_NAME} \
        quay.io/humancellatlas/secondary-analysis-mintegration /app/await_workflow_completion.py

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
        -e WORKFLOW_NAMES=ss2 \
        -e CROMWELL_URL="https://cromwell.mint-${LIRA_ENVIRONMENT}.broadinstitute.org" \
        -e CROMWELL_USER="${CROMWELL_USER}" \
        -e CROMWELL_PASSWORD="${CROMWELL_PASSWORD}" \
        -e TIMEOUT_MINUTES=120 \
        -e PYTHONUNBUFFERED=0 \
        --link ${LIRA_DOCKER_CONTAINER_NAME}:${LIRA_DOCKER_CONTAINER_NAME} \
        quay.io/humancellatlas/secondary-analysis-mintegration /app/await_workflow_completion.py
fi


# 10. Stop Lira
print_style "success" "Stopping Lira"
docker stop "${LIRA_DOCKER_CONTAINER_NAME}"
print_style "success" "Removing Lira"
docker rm -v "${LIRA_DOCKER_CONTAINER_NAME}"
print_style "success" "Test succeeded!"
