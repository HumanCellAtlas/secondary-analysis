#!/usr/bin/env bash

# This script carries out the following steps:
# 1. Clone Lira if needed
# 2. Get pipeline-tools version
# 3. Build or pull Lira image
# 4. Get pipeline versions
# 5. Create config.json
# 6. Start Lira
# 7. Send in notification
# 8. Poll Cromwell for completion
# 9. Stop Lira

# This script currently only works when run locally on a developer's machine,
# but is designed to be easy to adapt to running on a Jenkins or Travis VM.
#
# In addition to the parameters specified below, this script expects the following
# files to be available:
# -${env}_config.json: environment config json file (contains environment-specific Lira config)
# -${env}_secrets.json file (contains secrets for Lira)
# 
# The following parameters are required. 
# Versions can be a branch name, tag, or commit hash
#
# env
# The environment to use -- affects Cromwell url, buckets, Lira config.
# When running from a PR, this will always be int. When running locally,
# the developer can choose dev or int.
#
# mint_deployment_dir
# Local directory where deployment TSVs can be found. Later, we'll
# create a repo for this, and this script will be modified to look there.
#
# lira_mode and lira_version
# The lira_mode param can be "local", "image" or "github".
# If "local" is specified, a local copy of the Lira code is used and
# lira_version is ignored.
# 
# If "image" is specified, this script will pull and run
# a particular version of the Lira docker image specified by lira_version.
# If lira_version == "latest_released", then the script will scan the GitHub repo
# for the highest tagged version and try to pull an image with the same version.
# If lira_version == "latest_deployed", then the script will use the latest
# deployed version in env, specified in the deployment tsv. If lira_version is
# any other value, then it is assumed to be a docker image tag version and
# this script will attempt to pull that version.
#
# Running in "github" mode causes this script to clone the Lira repo and check
# out a specific branch, tag, or commit to use, specified by lira_version.
#
# pipeline_tools_mode and pipeline_tools_version
# If pipeline_tools_mode == "local", then a local copy of the repo is used,
# with the path to the repo specified in pipeline_tools_version. If pipeline_tools_version
# is "latest_deployed" then the latest version from the deployment tsv is used.

# If pipeline_tools_mode == "github", then the script configures Lira to read the
# wrapper WDLS from GitHub and to use version pipeline_tools_version. Also, if lira_mode
# is "local", then it will get built using that pipeline_tools_version.
#
# tenx_mode and tenx_version
# When tenx_mode == "local", this script will configure lira to use the 10x wdl
# in a local directory specified by tenx_version.
#
# When tenx_mode == "github", this script will configure lira to use the 10x wdl
# in the skylab repo, with branch, tag, or commit specified by tenx_version.
# If tenx_version == "latest_deployed", then this script will find the latest
# wdl version in the mint deployment TSV and configure lira to read that version
# from GitHub.
#
# ss2_mode and ss2_version
# The ss2_mode and ss2_version params work in the same way as tenx_mode and
# tenx_version.

set -e

env=$1
mint_deployment_dir=$2
lira_mode=$3
lira_version=$4
pipeline_tools_mode=$5
pipeline_tools_version=$6
tenx_mode=$7
tenx_version=$8
ss2_mode=$9
ss2_version=${10}

work_dir=$(pwd)
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 1. Clone Lira if needed
if [ $lira_mode == "github" ]; then
  git clone git@github.com:HumanCellAtlas/lira.git
  lira_dir=lira
  cd $lira_dir
  if [ $lira_version == "latest_released" ]; then
    lira_version=$(python $script_dir/get_latest_release.py HumanCellAtlas/lira)
  elif [ $lira_version == "latest_deployed" ]; then
    lira_version=$(python $script_dir/current_deployed_version.py lira)
  fi
  git checkout $lira_version
  cd -
elif [ $lira_mode == "local" ]; then
  lira_dir=$lira_version
fi

# 2. Get pipeline-tools version
if [ $pipeline_tools_mode == "github" ]; then
  if [ $pipeline_tools_version == "latest_deployed" ]; then
    pipeline_tools_version=$(python $script_dir/current_deployed_version.py \
                      --mint_deployment_dir $mint_deployment_dir \
                      --env $env \
                      --component_name pipeline_tools)
    echo "pipeline_tools_version: $pipeline_tools_version"
  fi
  pipeline_tools_prefix="https://raw.githubusercontent.com/HumanCellAtlas/pipeline-tools/${pipeline_tools_version}"
elif [ $pipeline_tools_mode == "local" ]; then
  pipeline_tools_prefix="/pipeline-tools"
  pipeline_tools_dir=$pipeline_tools_version
  cd $pipeline_tools_dir
  pipeline_tools_dir=$(pwd)
  cd -
fi

# 3. Build or pull Lira image
if [ $lira_mode == "image" ]; then
  if [ $lira_version == "latest_released" ]; then
    lira_image_version=$(python $script_dir/get_latest_release.py HumanCellAtlas/lira)
  elif [ $lira_version == "latest_deployed" ]; then
    lira_image_version=$(python $script_dir/current_deployed_version.py lira)
  else
    lira_image_version=$lira_version
  fi
  echo "Not pulling lira image -- fix this"
  #docker pull humancellatlas/lira:$lira_image_version
elif [ $lira_mode == "local" ] || [ $lira_mode == "github" ]; then
  cd $lira_dir
  if [ $lira_mode == "local" ]; then
    lira_image_version=local
  elif [ $lira_mode == "github" ]; then
    lira_image_version=$lira_version
  fi
  echo "Building Lira version: $lira_image_version"
  docker build -t humancellatlas/lira:$lira_image_version .
  cd -
fi

# 4. Get analysis pipeline versions to use
if [ $tenx_mode == "github" ]; then
  if [ $tenx_version == "latest_deployed" ]; then
    tenx_version=$(python $script_dir/current_deployed_version.py \
                      --mint_deployment_dir $mint_deployment_dir \
                      --env $env \
                      --component_name 10x)
    echo "10x version: $tenx_version"
  fi
  tenx_prefix="https://raw.githubusercontent.com/HumanCellAtlas/skylab/${tenx_version}"
elif [ $tenx_mode == "local" ]; then
  tenx_dir=$tenx_version
  cd $tenx_dir
  tenx_dir=$(pwd)
  cd -
  tenx_prefix="/10x"
fi

if [ $ss2_mode == "github" ]; then
  if [ $ss2_version == "latest_deployed" ]; then
    ss2_version=$(python $script_dir/current_deployed_version.py \
                      --mint_deployment_dir $mint_deployment_dir \
                      --env $env \
                      --component_name ss2)
    echo "ss2 version: $ss2_version"
  fi
  ss2_prefix="https://raw.githubusercontent.com/HumanCellAtlas/skylab/${ss2_version}"
elif [ $ss2_mode == "local" ]; then
  ss2_dir=$ss2_version
  cd $ss2_dir
  ss2_dir=$(pwd)
  cd -
  ss2_prefix="/ss2"
fi

# 5. Create config.json
# (TODO: Use Henry's script here)
# TODO: use config file from config repo
# dev_secrets.json will come from Vault eventually
echo "Creating Lira config"
python $script_dir/create_lira_config.py \
    --env_config_file ${env}_config.json \
    --secrets_file ${env}_secrets.json \
    --tenx_prefix $tenx_prefix \
    --ss2_prefix $ss2_prefix \
    --pipeline_tools_prefix $pipeline_tools_prefix > config.json

#echo "Exiting early"
#exit 0

# 6. Start Lira
echo "Starting Lira docker image"
# TODO: If pipeline_tools_mode is local, mount pipeline-tools dir when running Lira
if [ $pipeline_tools_mode == "local" ]; then
  mount_pipeline_tools="-v $pipeline_tools_dir:/pipeline-tools"
fi
if [ $tenx_mode == "local" ]; then
  mount_tenx="-v $tenx_dir:/10x"
fi
if [ $ss2_mode == "local" ]; then
  mount_ss2="-v $ss2_dir:/ss2"
fi
lira_image_id=$(docker run \
                -p 8080:8080 \
                -d \
                -e listener_config=/etc/secondary-analysis/config.json \
                -e GOOGLE_APPLICATION_CREDENTIALS=/etc/secondary-analysis/bucket-reader-key.json \
                -v $work_dir:/etc/secondary-analysis \
                $(echo "$mount_pipeline_tools" | xargs) \
                $(echo "$mount_tenx" | xargs) \
                $(echo "$mount_ss2" | xargs) \
                humancellatlas/lira:$lira_image_version)

# 7. Send in notifications
# TODO: Check in notifications to repo where integration_test.sh will live so they are accessible outside Lira repo
echo "Sending in notifications"
virtualenv integration-test-env
source integration-test-env/bin/activate
pip install requests
tenx_workflow_id=$(python $script_dir/send_notification.py \
                  --lira_url "http://localhost:8080/notifications" \
                  --secrets_file ${env}_secrets.json \
                  --notification $script_dir/10x_notification_${env}.json)
ss2_workflow_id=$(python $script_dir/send_notification.py \
                  --lira_url "http://localhost:8080/notifications" \
                  --secrets_file ${env}_secrets.json \
                  --notification $script_dir/ss2_notification_${env}.json)
echo "tenx_workflow_id: $tenx_workflow_id"
echo "ss2_workflow_id: $ss2_workflow_id"

# 8. Poll for completion
echo "Awaiting workflow completion"
python $script_dir/await_workflow_completion.py \
  --workflow_ids $ss2_workflow_id,$tenx_workflow_id \
  --workflow_names ss2,10x \
  --cromwell_url https://cromwell.mint-$env.broadinstitute.org \
  --secrets_file ${env}_secrets.json \
  --timeout_minutes 20

# 9. Stop listener
echo "Stopping Lira"
docker stop $lira_image_id
