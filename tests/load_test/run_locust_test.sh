#!/usr/bin/env bash

set -e

ENV=$1
UI=$2
USERS=${3:-1000}
HATCH_RATE=${4:-100}
LIMIT=${5:-10}


error=0
if [ -z $1 ]; then
    echo -e "\nYou must specify a environment, either 'local' or the full URL to the Lira instance, e.g. 'https://pipelines.dev.data.humancellatlas.org'(DO NOT include the endpoint!)"
    error=1
fi

if [ -z $2 ]; then
    echo -e "\nYou must choose whether to use UI or not! i.e. true/false"
    error=1
fi

if [ -z $3 ]; then
    echo -e "\nYou might want to specify the number of simulated users, using 1000 by default."
fi

if [ -z $4 ]; then
    echo -e "\nYou might want to specify the hatch rate of simulated users per second, using 100 by default."
fi

if [ -z $5 ]; then
    echo -e "\nYou might want to specify the number of requests, after which the test will terminate automatically, using 10 by default."
fi

if [ $error -eq 1 ]; then
    echo -e "\nUsage: bash run_locust_test.sh ENV UI USERS HATCH_RATE LIMIT. e.g. bash run_locust_test.sh https://pipelines.dev.data.humancellatlas.org false 1000 100 10\n"
    exit 1
fi

if [ $ENV == "local" ]; then
    if [ ${UI} = true ]; then
        echo -e "Go to the UI at http://localhost:8089 to start the test"
        locust -f locust_test.py --host http://localhost:8080
    else
        locust -f locust_test.py --host http://localhost:8080 --no-web -c ${USERS} -r ${HATCH_RATE} -n ${LIMIT} --csv=./data/results/locust_load_test_result_$(date '+%Y%m%d-%H%M%S')
        echo -e "Saving testing results in ./data/results/"
    fi
else
    if [ ${UI} = true ]; then
        echo -e "Go to the UI at http://localhost:8089 to start the test"
        locust -f locust_test.py --host ${ENV}
    else
        locust -f locust_test.py --host ${ENV} --no-web -c ${USERS} -r ${HATCH_RATE} -n ${LIMIT} --csv=./data/results/locust_load_test_result_$(date '+%Y%m%d-%H%M%S')
        echo -e "Saving testing results in ./data/results/"
    fi
fi
