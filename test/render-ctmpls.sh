#!/usr/bin/env bash

env=$1
vault_token=$2

printf "Creating Lira config\n"
docker run -it --rm -v $PWD:/working -e VAULT_TOKEN=$vault_token \
    -e INPUT_PATH=/working/test/config \
    -e OUT_PATH=/working/test \
    broadinstitute/dsde-toolbox render-templates.sh $env