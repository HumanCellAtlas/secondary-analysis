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
# If "local" is specified, a local copy of the Lira code is used. In this case,
# lira_version should be the local path to the repo.
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
# These parameters determine where Lira will look for adapter WDLs.
# (pipeline-tools is also used as a Python library for Lira, but that version
# is controlled in Lira's Dockerfile).
# If pipeline_tools_mode == "local", then a local copy of the repo is used,
# with the path to the repo specified in pipeline_tools_version.
#
# If pipeline_tools_mode == "github", then the script configures Lira to read the
# wrapper WDLS from GitHub and to use version pipeline_tools_version.
# If pipeline_tools_version is "latest_released", then the latest tagged release
# in GitHub will be used. If pipeline_tools_version is "latest_deployed" then
# the latest version from the deployment tsv is used.
#
# tenx_mode and tenx_version
# When tenx_mode == "local", this script will configure lira to use the 10x wdl
# in a local directory specified by tenx_version.
#
# When tenx_mode == "github", this script will configure lira to use the 10x wdl
# in the skylab repo, with branch, tag, or commit specified by tenx_version.
# If tenx_version == "latest_deployed", then this script will find the latest
# wdl version in the mint deployment TSV and configure lira to read that version
# from GitHub. If tenx_version == "latest_released" then this script will use
# the latest tagged release in GitHub.
#
# ss2_mode and ss2_version
# The ss2_mode and ss2_version params work in the same way as tenx_mode and
# tenx_version.
#
# env_config_json
# Path to file containing environment name and subscription ids
#
# secrets_json
# Path to secrets file

printf "\nStarting integration test\n"
date +"%Y-%m-%d %H:%M:%S"

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
env_config_json=${11}
secrets_json=${12}

work_dir=$(pwd)
script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

printf "\n\nenv: $env"
printf "\nmint_deployment_dir: $mint_deployment_dir"
printf "\nlira_mode: $lira_mode"
printf "\nlira_version: $lira_version"
printf "\npipeline_tools_mode: $pipeline_tools_mode"
printf "\npipeline_tools_version: $pipeline_tools_version"
printf "\ntenx_mode: $tenx_mode"
printf "\ntenx_version: $tenx_version"
printf "\nss2_mode: $ss2_mode"
printf "\nss2_version: $ss2_version"
printf "\nenv_config_json: $env_config_json"
printf "\nsecrets_json: $secrets_json"

printf "\n\nWorking directory: $work_dir"
printf "\nScript directory: $script_dir"

# 1. Clone Lira if needed
if [ $lira_mode == "github" ]; then
  printf "\n\nCloning lira"
  git clone git@github.com:HumanCellAtlas/lira.git
  lira_dir=lira
  cd $lira_dir
  if [ $lira_version == "latest_released" ]; then
    printf "\nDetermining latest release tag"
    lira_version=$(python $script_dir/get_latest_release.py --repo HumanCellAtlas/lira)
  elif [ $lira_version == "latest_deployed" ]; then
    printf "\nDetermining latest deployed version"
    lira_version=$(python $script_dir/current_deployed_version.py \
                    --component_name lira
                    --env $env \
                    --mint_deployment_dir $mint_deployment_dir)
  fi
  printf "\nChecking out $lira_version"
  git checkout $lira_version
  cd $work_dir
elif [ $lira_mode == "local" ]; then
  printf "\n\nUsing Lira in dir: $lira_version\n"
  lira_dir=$lira_version
fi

# 2. Get pipeline-tools version
if [ $pipeline_tools_mode == "github" ]; then
  if [ $pipeline_tools_version == "latest_released" ]; then
    printf "\n\nDetermining latest released version of pipeline-tools"
    pipeline_tools_version=$(python $script_dir/get_latest_release.py --repo HumanCellAtlas/pipeline-tools)
  elif [ $pipeline_tools_version == "latest_deployed" ]; then
    printf "\n\nDetermining latest deployed version of pipeline-tools"
    pipeline_tools_version=$(python $script_dir/current_deployed_version.py \
                      --mint_deployment_dir $mint_deployment_dir \
                      --env $env \
                      --component_name pipeline_tools)
  fi
  printf "\nConfiguring Lira to use adapter wdls from pipeline-tools GitHub repo, version: $pipeline_tools_version"
  pipeline_tools_prefix="https://raw.githubusercontent.com/HumanCellAtlas/pipeline-tools/${pipeline_tools_version}"
elif [ $pipeline_tools_mode == "local" ]; then
  pipeline_tools_prefix="/pipeline-tools"
  pipeline_tools_dir=$pipeline_tools_version
  cd $pipeline_tools_dir
  pipeline_tools_dir=$(pwd)
  cd $work_dir
  printf "\n\nConfiguring Lira to use adapter wdls in dir: $pipeline_tools_dir"
fi

# 3. Build or pull Lira image
if [ $lira_mode == "image" ]; then
  if [ $lira_version == "latest_released" ]; then
    printf "\n\nDetermining latest released version of Lira"
    lira_image_version=$(python $script_dir/get_latest_release.py --repo HumanCellAtlas/lira)
  elif [ $lira_version == "latest_deployed" ]; then
    printf "\n\nDetermining latest deployed version of Lira"
    lira_image_version=$(python $script_dir/current_deployed_version.py lira)
  else
    lira_image_version=$lira_version
  fi
  printf "\nNot pulling lira_image_version: $lira_image_version -- fix this\n"
  #docker pull humancellatlas/lira:$lira_image_version
elif [ $lira_mode == "local" ] || [ $lira_mode == "github" ]; then
  cd $lira_dir
  if [ $lira_mode == "local" ]; then
    lira_image_version=local
  elif [ $lira_mode == "github" ]; then
    lira_image_version=$lira_version
  fi
  printf "\n\nBuilding Lira version \"$lira_image_version\" from dir: $lira_dir\n"
  docker build -t humancellatlas/lira:$lira_image_version .
  cd $work_dir
fi

# 4. Get analysis pipeline versions to use
if [ $tenx_mode == "github" ]; then
  if [ $tenx_version == "latest_released" ]; then
    printf "\n\nDetermining latest released version of 10x pipeline"
    tenx_version=$(python $script_dir/get_latest_release.py --repo HumanCellAtlas/skylab --tag_prefix 10x_)
  elif [ $tenx_version == "latest_deployed" ]; then
    printf "\n\nDetermining latest deployed version of 10x pipeline"
    tenx_version=$(python $script_dir/current_deployed_version.py \
                      --mint_deployment_dir $mint_deployment_dir \
                      --env $env \
                      --component_name 10x)
  fi
  tenx_prefix="https://raw.githubusercontent.com/HumanCellAtlas/skylab/${tenx_version}"
  printf "\nConfiguring Lira to use 10x wdl from skylab Github repo, version: $tenx_version"
elif [ $tenx_mode == "local" ]; then
  tenx_dir=$tenx_version
  cd $tenx_dir
  tenx_dir=$(pwd)
  cd $work_dir
  tenx_prefix="/10x"
  printf "\n\nUsing 10x wdl in dir: $tenx_dir"
fi

if [ $ss2_mode == "github" ]; then
  if [ $ss2_version == "latest_released" ]; then
    printf "\n\nDetermining latest released version of ss2 pipeline"
    ss2_version=$(python $script_dir/get_latest_release.py --repo HumanCellAtlas/skylab --tag_prefix ss2_)
  elif [ $ss2_version == "latest_deployed" ]; then
    printf "\n\nDetermining latest deployed version of ss2 pipeline"
    ss2_version=$(python $script_dir/current_deployed_version.py \
                      --mint_deployment_dir $mint_deployment_dir \
                      --env $env \
                      --component_name ss2)
  fi
  printf "\nConfiguring Lira to use ss2 wdl from skylab GitHub repo, version: $ss2_version"
  ss2_prefix="https://raw.githubusercontent.com/HumanCellAtlas/skylab/${ss2_version}"
elif [ $ss2_mode == "local" ]; then
  ss2_dir=$ss2_version
  cd $ss2_dir
  ss2_dir=$(pwd)
  cd $work_dir
  ss2_prefix="/ss2"
  printf "\n\nUsing ss2 wdl in dir: $ss2_dir"
fi

# 5. Create config.json
# (TODO: Use Henry's script here)
# TODO: use config file from config repo
# dev_secrets.json will come from Vault eventually
printf "\n\nCreating Lira config"
printf "\nUsing $env_config_json"
printf "\nUsing $secrets_json"
python $script_dir/create_lira_config.py \
    --env_config_file $env_config_json \
    --secrets_file $secrets_json \
    --tenx_prefix $tenx_prefix \
    --ss2_prefix $ss2_prefix \
    --pipeline_tools_prefix $pipeline_tools_prefix > config.json

# 6. Start Lira
printf "\n\nStarting Lira docker image"
if [ $pipeline_tools_mode == "local" ]; then
  mount_pipeline_tools="-v $pipeline_tools_dir:/pipeline-tools"
  printf "\nMounting pipeline_tools_dir: $pipeline_tools_dir"
fi
if [ $tenx_mode == "local" ]; then
  mount_tenx="-v $tenx_dir:/10x"
  printf "\nMounting tenx_dir: $tenx_dir"
fi
if [ $ss2_mode == "local" ]; then
  mount_ss2="-v $ss2_dir:/ss2"
  printf "\nMounting ss2_dir: $ss2_dir"
fi
lira_container_id=$(docker run \
                -p 8080:8080 \
                -d \
                -e listener_config=/etc/secondary-analysis/config.json \
                -e GOOGLE_APPLICATION_CREDENTIALS=/etc/secondary-analysis/bucket-reader-key.json \
                -v $work_dir:/etc/secondary-analysis \
                $(echo "$mount_pipeline_tools" | xargs) \
                $(echo "$mount_tenx" | xargs) \
                $(echo "$mount_ss2" | xargs) \
                humancellatlas/lira:$lira_image_version)
printf "\nLira container id: $lira_container_id"

# 7. Send in notifications
printf "\n\nSending in notifications\n"
virtualenv integration-test-env
source integration-test-env/bin/activate
pip install requests
#tenx_workflow_id=$(python $script_dir/send_notification.py \
#                  --lira_url "http://localhost:8080/notifications" \
#                  --secrets_file ${env}_secrets.json \
#                  --notification $script_dir/10x_notification_${env}.json)
ss2_workflow_id=$(python $script_dir/send_notification.py \
                  --lira_url "http://localhost:8080/notifications" \
                  --secrets_file ${env}_secrets.json \
                  --notification $script_dir/ss2_notification_${env}.json)
printf "\ntenx_workflow_id: $tenx_workflow_id"
printf "\nss2_workflow_id: $ss2_workflow_id"

# 8. Poll for completion
printf "\n\nAwaiting workflow completion\n"
set +e
function stop_lira_on_error {
  lira_container_id=$1
  printf "\n\nStopping Lira\n"
  docker stop $lira_container_id
  printf "\n\nTest failed!\n\n"
  exit 1
}

trap "stop_lira_on_error $lira_container_id" ERR
#python $script_dir/await_workflow_completion.py \
#  --workflow_ids $ss2_workflow_id,$tenx_workflow_id \
#  --workflow_names ss2,10x \
#  --cromwell_url https://cromwell.mint-$env.broadinstitute.org \
#  --secrets_file ${env}_secrets.json \
#  --timeout_minutes 120
python $script_dir/await_workflow_completion.py \
  --workflow_ids $ss2_workflow_id \
  --workflow_names ss2 \
  --cromwell_url https://cromwell.mint-$env.broadinstitute.org \
  --secrets_file ${env}_secrets.json \
  --timeout_minutes 20 \
  --poll_interval_seconds 10

# 9. Stop Lira
printf "\n\nStopping Lira\n"
docker stop $lira_container_id
printf "\n\nTest succeeded!\n\n"
