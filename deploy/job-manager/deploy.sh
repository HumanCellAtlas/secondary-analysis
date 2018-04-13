#!/usr/bin/env bash

# This script is designed to be run by Jenkins to deploy a new Job Manager kubernetes deployment
# =======================================
# Example Usage:
# bash deploy.sh dev v0.0.4 username password
# =======================================

function line() {
    echo -ne "=======================================\n"
}

function stdout() {
    local MSG=$1
    echo -ne ">| Current Step |< ${MSG} ...\n"
}

function stderr() {
    echo -ne ">>| Error Occurred |<< - exiting ...\n"
    exit 1
}

function configure_mint_kubernetes() {
    local ENV=$1

    stdout "Setting to use Google project: project broad-dsde-mint-${ENV}"
    gcloud config set project broad-dsde-mint-${ENV}

    stdout "Setting to use GKE cluster: project gke_broad-dsde-mint-${ENV}_us-central1-b_listener"
    kubectl config use-context gke_broad-dsde-mint-${ENV}_us-central1-b_listener
}

function update_submodule() {
    local JM_TAG=$1
    local TOP_LEVEL=$(git rev-parse --show-toplevel)

    stdout "Updating submodule"
    git submodule update --recursive --remote

    cd "${TOP_LEVEL}/deploy/job-manager/job-manager" && git checkout ${JM_TAG} && cd -
}

function render_environment_ts() {
    local CLIENT_ID=""

    stdout "Rendering environment.prod.ts for Job Manager UI"
    docker run -i --rm \
        -e CLIENT_ID=${CLIENT_ID} \
        -v ${PWD}:/working broadinstitute/dsde-toolbox:k8s \
        /usr/local/bin/render-ctmpl.sh -k /working/environment.template.ts.ctmpl
}

function inject_angular_and_build_UI() {
    local ENV=$1
    local DOCKER_TAG=$2
    local TOP_LEVEL=$(git rev-parse --show-toplevel)

    stdout "Configuring docker for gcloud"
    yes | gcloud auth configure-docker

    stdout "Injecting environment.prod.ts into submodule for Job Manager UI"
    cp "${TOP_LEVEL}/deploy/job-manager/environment.template.ts" "${TOP_LEVEL}/deploy/job-manager/job-manager/ui/src/environments/environment.prod.ts"

    stdout "Building UI docker image: gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-ui:${DOCKER_TAG}"
    docker build -t gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-ui:${DOCKER_TAG} "${TOP_LEVEL}/deploy/job-manager/job-manager/ui" -f "${TOP_LEVEL}/deploy/job-manager/job-manager/ui/Dockerfile"

    stdout "Pushing UI docker image: gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-ui:${DOCKER_TAG}"
    docker push gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-ui:${DOCKER_TAG}

    stdout "Resetting the state of submodule after injection"
    pushd ${TOP_LEVEL}/deploy/job-manager/job-manager
    git reset --hard HEAD
    popd
}

function build_API() {
    local ENV=$1
    local DOCKER_TAG=$2
    local TOP_LEVEL=$(git rev-parse --show-toplevel)

    # Let gcloud to build and push the API container
    stdout "Building API docker image: gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-api:${DOCKER_TAG}"
    docker build -t gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-api:${DOCKER_TAG} "${TOP_LEVEL}/deploy/job-manager/job-manager" -f "${TOP_LEVEL}/deploy/job-manager/job-manager/servers/cromwell/Dockerfile"

    stdout "Pushing API docker image: gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-api:${DOCKER_TAG}"
    docker push gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-api:${DOCKER_TAG}
}

function create_API_config() {
    local ENV=$1
    local CONFIG_NAME=$2
    local VAULT_TOKEN_FILE=$3

    CROMWELL_USR=$(docker run -it --rm -v ${VAULT_TOKEN_FILE}:/root/.vault-token broadinstitute/dsde-toolbox vault read -field=cromwell_user secret/dsde/mint/${ENV}/common/htpasswd)
    CROMWELL_PWD=$(docker run -it --rm -v ${VAULT_TOKEN_FILE}:/root/.vault-token broadinstitute/dsde-toolbox vault read -field=cromwell_password secret/dsde/mint/${ENV}/common/htpasswd)

    stdout "Rendering API's config.json file"
    docker run -i --rm \
        -e CROMWELL_USR=${CROMWELL_USR} \
        -e CROMWELL_PWD=${CROMWELL_PWD} \
        -v ${PWD}:/working broadinstitute/dsde-toolbox:k8s \
        /usr/local/bin/render-ctmpl.sh -k /working/api-config.json.ctmpl

    stdout "Creating API config secret object: ${CONFIG_NAME}"
    kubectl create secret generic ${CONFIG_NAME} --from-file=config=./api-config.json
}

function create_API_capabilities_conf() {
    local CONFIG_NAME=$1

    stdout "Creating API Capabilities config configMap object: ${CONFIG_NAME}"
    kubectl create configmap ${CONFIG_NAME} --from-file=capabilities-config=capabilities_config.json
}

function create_UI_conf() {
    local CONFIG_NAME=$1
    local JM_VERSION=$2

    stdout "Rendering UI's nginx.conf file"
    docker run -i --rm \
        -e JM_VERSION=${JM_VERSION} \
        -v ${PWD}:/working broadinstitute/dsde-toolbox:k8s \
        /usr/local/bin/render-ctmpl.sh -k /working/nginx.conf.ctmpl

    stdout "Creating UI config configMap object: ${CONFIG_NAME}"
    kubectl create configmap ${CONFIG_NAME} --from-file=jm-ui-config=nginx.conf
}

function create_UI_proxy() {
    # NOTE: THIS MIGHT NEED TO ME MOUNTED FROM VAULT DIRECTLY for Jenkins Jobs!!!
    local USERNAME=$1
    local PASSWORD=$2
    local CONFIG_NAME=$3

    stdout "Generating Apache proxy based on inputted username and password"
    htpasswd -b -c ./.htpasswd ${USERNAME} ${PASSWORD}

    stdout "Creating UI proxy secret object: ${CONFIG_NAME}"
    kubectl create secret generic ${CONFIG_NAME} --from-file=htpasswd=.htpasswd
}

function apply_kube_deployment() {
    local ENV=$1
    local API_DOCKER_IMAGE=$2
    local API_CONFIG=$3
    local API_CAPABILITIES_CONFIG=$4
    local UI_DOCKER_IMAGE=$5
    local PROXY_CREDENTIALS_CONFIG=$6
    local UI_CONFIG=$7
    local API_PATH_PREFIX="/api/v1"
    local CROMWELL_URL="https://cromwell.mint-${ENV}.broadinstitute.org/api/workflows/v1"
    local REPLICAS=1

    stdout "Rendering job-manager-deployment.yaml file"
    docker run -i --rm \
        -e REPLICAS=${REPLICAS} \
        -e API_DOCKER_IMAGE=${API_DOCKER_IMAGE} \
        -e API_PATH_PREFIX=${API_PATH_PREFIX} \
        -e CROMWELL_URL=${CROMWELL_URL} \
        -e UI_DOCKER_IMAGE=${UI_DOCKER_IMAGE} \
        -e API_CONFIG=${API_CONFIG} \
        -e PROXY_CREDENTIALS_CONFIG=${PROXY_CREDENTIALS_CONFIG} \
        -e UI_CONFIG=${UI_CONFIG} \
        -e API_CAPABILITIES_CONFIG=${API_CAPABILITIES_CONFIG} \
        -v ${PWD}:/working broadinstitute/dsde-toolbox:k8s \
        /usr/local/bin/render-ctmpl.sh -k /working/job-manager-deployment.yaml.ctmpl

    stdout "Applying job-manager-deployment.yaml"
    kubectl apply -f job-manager-deployment.yaml
}

function apply_kube_service() {
    stdout "Applying job-manager-service.yaml"
    kubectl apply -f job-manager-service.yaml
}

function apply_kube_ingress() {
    local ENV=$1
    local EXTERNAL_IP_NAME="job-manager"
    local TLS_SECRET_NAME="${ENV}-mint-ssl"
    # TODO: Mount tls cert and key files from Vault and create TLS SECRET k8s cluster
    # local VAULT_TOKEN_FILE

    stdout "Rendering job-manager-ingress.yaml file"
    docker run -i --rm \
        -e EXTERNAL_IP_NAME=${EXTERNAL_IP_NAME} \
        -e TLS_SECRET_NAME=${TLS_SECRET_NAME} \
        -v ${PWD}:/working broadinstitute/dsde-toolbox:k8s \
        /usr/local/bin/render-ctmpl.sh -k /working/job-manager-ingress.yaml.ctmpl

    stdout "Applying job-manager-ingress.yaml"
    kubectl apply -f job-manager-ingress.yaml
}

function tear_down_kube_secret() {
    local filename=$1

    stdout "Tearing down secret objects on Kubernetes cluster"
    kubectl delete secret ${filename}
}

function tear_down_kube_configMap() {
    local filename=$1

    stdout "Tearing down configMap objects on Kubernetes cluster"
    kubectl delete configmap ${filename}
}

function tear_down_rendered_files() {

    stdout "Removing all generated files"
    rm -rf ".htpasswd"
    rm -rf "api-config.json"
    rm -rf "environment.template.ts"
    rm -rf "job-manager-deployment.yaml"
    rm -rf "job-manager-ingress.yaml"
    rm -rf "nginx.conf"
}

# The main function to execute all steps of a deployment of Job Manager
function main() {
    local ENV=$1
    local JM_TAG=$2
    local JMUI_USR=$3
    local JMUI_PWD=$4
    local VAULT_TOKEN_FILE=${5:-"$HOME/.vault-token"}

    local DOCKER_TAG=${JM_TAG}
    local API_DOCKER_IMAGE="gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-api:${DOCKER_TAG}"
    local UI_DOCKER_IMAGE="gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-ui:${DOCKER_TAG}"

    set -e

    line
    configure_mint_kubernetes ${ENV}

    line
    update_submodule ${JM_TAG}

    line
    render_environment_ts

    line
    inject_angular_and_build_UI ${ENV} ${DOCKER_TAG}

    line
    build_API ${ENV} ${DOCKER_TAG}

    local API_CONFIG="cromwell-credentials-$(date '+%Y-%m-%d-%H-%M')"

    local CAPABILITIES_CONFIG="capabilities-config-$(date '+%Y-%m-%d-%H-%M')"

    local USERNAME=${JMUI_USR}
    local PASSWORD=${JMUI_PWD}
    local UI_PROXY="jm-htpasswd-$(date '+%Y-%m-%d-%H-%M')"

    local UI_CONFIG="jm-ui-config-$(date '+%Y-%m-%d-%H-%M')"

    line
    if create_API_config ${ENV} ${API_CONFIG} ${VAULT_TOKEN_FILE} && create_API_capabilities_conf ${CAPABILITIES_CONFIG} && create_UI_proxy ${USERNAME} ${PASSWORD} ${UI_PROXY} && create_UI_conf ${UI_CONFIG} ${JM_TAG}
    then
        stdout "Successfully created all config files on Kubernetes cluster"
    else
        tear_down_kube_secret ${API_CONFIG}
        tear_down_kube_secret ${UI_PROXY}
        tear_down_kube_configMap ${CAPABILITIES_CONFIG}
        tear_down_kube_configMap ${UI_CONFIG}
        stderr
    fi

    line
    apply_kube_service

    line
    apply_kube_deployment ${ENV} ${API_DOCKER_IMAGE} ${API_CONFIG} ${CAPABILITIES_CONFIG} ${UI_DOCKER_IMAGE} ${UI_PROXY} ${UI_CONFIG}

#    line
#    Each re-deployment to the ingress will cause a ~10 minuted downtime to the Job Manager. So this script assumes that you have created your ingress before using this it. This functions is here just for completeness.
#    TODO: Add back the ingress set up step if needed
#    apply_kube_ingress ${ENV}

    line
    tear_down_rendered_files
}

# Main Runner:
error=0
if [ -z $1 ]; then
    echo -e "\nYou must specify a deployment environment!"
    error=1
fi

if [ -z $2 ]; then
    echo -e "\nYou must specify a Job Manager Git Tag!"
    error=1
fi

if [ -z $3 ]; then
    echo -e "\nYou must specify a desired username for Job Manager UI!"
    error=1
fi

if [ -z $4 ]; then
    echo -e "\nYou must specify a desired password for Job Manager UI!"
    error=1
fi

if [ -z $5 ]; then
    echo -e "\nMissing the Vault token file under $HOME/.vault-token, you need to make sure you have passed in the path to the token file as the 5th argument of this script!"
fi

if [ $error -eq 1 ]; then
    echo -e "\nUsage: bash deploy.sh ENV(dev/staging/test) GIT_TAG USERNAME PASSWORD VAULT_TOKEN_FILE(optional)\n"
    exit 1
fi

main $1 $2 $3 $4 $5
