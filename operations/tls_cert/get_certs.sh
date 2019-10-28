#!/usr/bin/env bash

working=$1
domain=$2

if [ $# -ne 2 ]; then
  echo -e "Usage: bash get_certs.sh working_dir domain\n\ne.g. bash get_certs.sh $pwd pipelines.dev.data.humancellatlas.org\n"
  exit 1
fi

docker build -t humancellatlas/secondary-analysis:0.0.1 .

docker run \
    -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
    -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
    -v $working:/working \
    humancellatlas/secondary-analysis:0.0.1 \
    bash -c \
    "cd /working && cp /certs/certbot-route53/certbot-route53.sh . && bash certbot-route53.sh --agree-tos --manual-public-ip-logging-ok --email mintteam@broadinstitute.org --domains $domain"
