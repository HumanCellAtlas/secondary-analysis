#!/usr/bin/env bash

env=$1
script_dir=$2
creds_file=$3

python2 $script_dir/check_workflows.py -cromwell_url "https://cromwell.mint-${env}.broadinstitute.org" -cromwell_credentials $creds_file
