#!/usr/bin/env bash

function usage() {
    # Show the script's usage and help messages
}

function get_updated_repo() {
    git submodule update --recursive --remote
}

function render_environment_ts() {
    local CLIENT_ID=""

    docker run -i --rm \
        -e CLIENT_ID=${CLIENT_ID} \
        -v ${VAULT_TOKEN_FILE}:/root/.vault-token \
        -v ${PWD}:/working broadinstitute/dsde-toolbox:k8s \
        /usr/local/bin/render-ctmpl.sh -k /working/environment.template.ts.ctmpl
}

function inject_angular_and_build_UI() {
    local ENV=$1
    local DOCKER_TAG=$2
    local TOP_LEVEL=$(git rev-parse --show-toplevel)

    # Copy environment.template.ts into the submodule
    cp "${TOP_LEVEL}/deploy/job-manager/environment.dev.ts" "${TOP_LEVEL}/deploy/job-manager/job-manager/ui/src/environments/environment.prod.ts"

    # Let gcloud to build and push the UI container
    gcloud docker -- build -t gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-ui:${DOCKER_TAG} . -f "${TOP_LEVEL}/deploy/job-manager/job-manager/ui/Dockerfile"
    gcloud docker -- push gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-ui:${DOCKER_TAG}

    # Reset submodule state
    pushd ${TOP_LEVEL}/deploy/job-manager/job-manager
    git reset --hard HEAD
    popd
}

function build_API() {
    local ENV=$1
    local DOCKER_TAG=$2
    local TOP_LEVEL=$(git rev-parse --show-toplevel)

    # Let gcloud to build and push the API container
    gcloud docker -- build -t gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-api:${DOCKER_TAG} . -f "${TOP_LEVEL}/deploy/job-manager/job-manager/servers/cromwell/Dockerfile"
    gcloud docker -- push gcr.io/broad-dsde-mint-${ENV}/jm-cromwell-api:${DOCKER_TAG}

}

function create_API_config() {

    local TIMESTAMP=$(date '+%Y-%m-%d-%H-%M')

    kubectl create secret generic cromwell-credentials-${TIMESTAMP} --from-file=config=./api-config.json
}

function create_UI_proxy() {
    # NOTE: THIS NEED TO ME MOUNTED FROM VAULT DIRECTLY!!!
    local username=$1
    local password=$2
    local TIMESTAMP=$(date '+%Y-%m-%d-%H-%M')

    htpasswd -b -c ./.htpasswd ${username} ${password}
    kubectl create secret generic jm-htpasswd-${TIMESTAMP} --from-file=htpasswd=.htpasswd

}

function create_UI_conf() {
    local TIMESTAMP=$(date '+%Y-%m-%d-%H-%M')

    kubectl create configmap jm-ui-config-${TIMESTAMP} --from-file=jm-ui-config=nginx.conf
}

function apply_kube_deployment() {
    local ENV
    local API_DOCKER_IMAGE
    local UI_DOCKER_IMAGE
    local API_CONFIG
    local PROXY_CREDENTIALS_CONFIG
    local UI_CONFIG
    local API_PATH_PREFIX="/api/v1"
    local CROMWELL_URL="https://cromwell.mint-${ENV}.broadinstitute.org"
    local VAULT_TOKEN_FILE


    docker run -i --rm \
        -e EXTERNAL_IP_NAME=job-manager \
        -e TLS_SECRET_NAME=staging-mint-ssl \
        -v ${VAULT_TOKEN_FILE}:/root/.vault-token \
        -v ${PWD}:/working broadinstitute/dsde-toolbox:k8s \
        /usr/local/bin/render-ctmpl.sh -k /working/job-manager-ingress.yaml.ctmpl

    kubectl apply -f job-manager-deployment.yaml
}

function apply_kube_service() {
    kubectl apply -f job-manager-service.yaml
}

function apply_kube_ingress() {
    local ENV
    local EXTERNAL_IP_NAME="job-manager"
    local TLS_SECRET_NAME="${ENV}-mint-ssl"
    local VAULT_TOKEN_FILE


    docker run -i --rm \
        -e EXTERNAL_IP_NAME=job-manager \
        -e TLS_SECRET_NAME=staging-mint-ssl \
        -v ${VAULT_TOKEN_FILE}:/root/.vault-token \
        -v ${PWD}:/working broadinstitute/dsde-toolbox:k8s \
        /usr/local/bin/render-ctmpl.sh -k /working/job-manager-ingress.yaml.ctmpl

    kubectl apply -f job-manager-ingress.yaml
}

function configure_env() {
    local ENV=$1

    gcloud config set project broad-dsde-mint-${ENV}
    kubectl config use-context gke_broad-dsde-mint-${ENV}_us-central1-b_listener
}

# The main function to execute all steps of a deployment of Job Manager
function main() {
    configure_env
    get_updated_repo
    inject_angular_and_build_UI
    build_API
    create_API_config
    create_UI_proxy
    create_UI_conf
    apply_kube_service
    apply_kube_deployment
    apply_kube_ingress

}

