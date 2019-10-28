#!/usr/bin/env python

from datetime import datetime
import argparse
import json
import string
import requests

workflow_names = [
    'AdapterSmartSeq2SingleCell',
    'SmartSeq2SingleCell',
    'RunHisat2RsemPipeline',
    'RunHisat2Pipeline',
    'total',
]
ignore_before = '2018-03-01T00:00:00.000Z'


def run(cromwell_url, user, password):
    auth = requests.auth.HTTPBasicAuth(user, password)

    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    name_to_count = {}
    for name in workflow_names:
        query_params = 'name={0}&status=Running&start={1}'.format(name, ignore_before)
        if name == 'total':
            query_params = 'status=Running&start={1}'.format(name, ignore_before)
        full_url = cromwell_url + '/api/workflows/v1/query?' + query_params
        count = query(full_url, auth)
        name_to_count[name] = count

    counts = map(lambda x: str(name_to_count[x]), workflow_names)
    log = now + '\t' + string.join(counts, '\t')
    print(log)


def query(url, auth):
    response = requests.get(url, auth=auth)
    count = 'unknown'
    if response.status_code == 200:
        response_js = response.json()
        count = response_js.get('totalResultsCount', 'unknown')
    return count


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('-cromwell_url')
    parser.add_argument('-cromwell_credentials')
    args = parser.parse_args()

    with open(args.cromwell_credentials) as f:
        credentials = json.load(f)

    run(args.cromwell_url, credentials['user'], credentials['password'])
