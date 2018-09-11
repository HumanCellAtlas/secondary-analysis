#!/usr/bin/env bash

# Restart greenbox services after running "stop_greenbox.sh"
# This script will re-create the Lira ingress and Falcon deployment to resume running analysis workflows

KUBE_CONTEXT=$1
KUBERNETES_NAMESPACE=$2
GLOBAL_IP_NAME="lira"
INGRESS_NAME="lira-ingress"
SERVICE_NAME="lira-service"
VAULT_TOKEN_PATH=${VAULT_TOKEN_PATH:-"${HOME}/.vault-token"}

if [ -z "${KUBE_CONTEXT}" ]; then
    echo -e "\nYou must specify a Kubernetes context to use"
    ERROR=1
fi

if [ "${ERROR}" -eq 1 ]; then
    echo -e "\nUsage: bash start_greenbox.sh KUBE_CONTEXT \n"
    exit 1
fi

kubectl config use-context "${KUBE_CONTEXT}"

# Get latest TLS secret
TLS_SECRET_NAME=$(kubectl get secrets -o json | jq -c '[.items[] | select(.metadata.name | contains("tls-secret"))][-1]' | jq -r .metadata.name)

echo "Re-create Lira ingress"
docker run -i --rm -e TLS_SECRET_NAME="${TLS_SECRET_NAME}" \
                   -e GLOBAL_IP_NAME="${GLOBAL_IP_NAME}" \
                   -e INGRESS_NAME="${INGRESS_NAME}" \
                   -e SERVICE_NAME="${SERVICE_NAME}" \
                   -v "${VAULT_TOKEN_PATH}":/root/.vault-token \
                   -v "${PWD}":/working \
                   broadinstitute/dsde-toolbox:ra_rendering \
                   /usr/local/bin/render-ctmpls.sh \
                   -k /working/lira-ingress.yaml.ctmpl

kubectl create -f lira-ingress.yaml --record --save-config --namespace="${KUBERNETES_NAMESPACE}"

# TODO: Uncomment when Falcon is deployed
#echo "Re-create Falcon deployment"
