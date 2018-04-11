#!/usr/bin/env bash

function stdout() {
    local msg=$1
    echo -ne ">| Current Step |< ${msg} ...\n"
}

function stderr() {
    local msg=$1
    echo -ne ${msg}
    echo -ne ">>| Error Occurred |<< - exiting ...\n"
    exit 1
}

function render_lira_config(){
    local ENV=${1:-"dev"}
    local DRY_RUN=${2:-"false"}
    local VAULT_TOKEN_FILE=${3:-"$HOME/.vault-token"}

    NOTIFICATION_TOKEN=$(docker run -it --rm -v ${VAULT_TOKEN_FILE}:/root/.vault-token broadinstitute/dsde-toolbox vault read -field=notification_token secret/dsde/mint/${ENV}/listener/listener_secret)
    CROMWELL_USERNAME=$(docker run -it --rm -v ${VAULT_TOKEN_FILE}:/root/.vault-token broadinstitute/dsde-toolbox vault read -field=cromwell_user secret/dsde/mint/${ENV}/common/htpasswd)
    CROMWELL_PASSWORD=$(docker run -it --rm -v ${VAULT_TOKEN_FILE}:/root/.vault-token broadinstitute/dsde-toolbox vault read -field=cromwell_password secret/dsde/mint/${ENV}/common/htpasswd)

    stdout "Rendering Lira's config.json file"
    docker run -i --rm \
        -e NOTIFICATION_TOKEN=${NOTIFICATION_TOKEN} \
        -e RUN_MODE=${DRY_RUN} \
        -e ENV=${ENV} \
        -e CROMWELL_USERNAME=${CROMWELL_USERNAME} \
        -e CROMWELL_PASSWORD=${CROMWELL_PASSWORD} \
        -v ${PWD}/data/lira_config:/working broadinstitute/dsde-toolbox:k8s \
        /usr/local/bin/render-ctmpl.sh -k /working/load_test_lira_config.json.ctmpl
}


error=0
if [ -z $1 ]; then
    echo -e "\nYou must specify a environment!"
    error=1
fi

if [ -z $2 ]; then
    echo -e "\nYou must specify whether to turn on the dry_run mode of Lira! (true/false)"
    error=1
fi

if [ -z $3 ]; then
    echo -e "\nMissing the Vault token file under $HOME/.vault-token, you might want to make sure you have passed in the path to the token file as the 3rd argument of this script!"
fi

if [ $error -eq 1 ]; then
    stderr "\nUsage: bash deploy.sh ENV(dev/staging/test) GIT_TAG USERNAME PASSWORD VAULT_TOKEN_FILE(optional)\n"
    exit 1
fi

render_lira_config $1 $2 $3
