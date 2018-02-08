#!/usr/bin/env python

import argparse
import json
import requests
import os

def run(args):
    with open(args.notification) as f:
        notification = json.load(f)

    token = args.notification_token
    full_url = args.lira_url + '?auth={0}'.format(token)

    response = requests.post(full_url, json=notification)    
    if response.status_code == 201:
        response_json = response.json()
        workflow_id = response_json['id']
        print(workflow_id)
    else:
        msg = 'Unexpected response code {0} when sending notification {1} to url {2}: \n{3}'
        raise ValueError(msg.format(response.status_code, args.notification, args.lira_url, response.text))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--lira_url', default=os.environ.get('LIRA_URL', None))
    parser.add_argument('--notification_token', default=os.environ.get('NOTIFICATION_TOKEN', None))
    parser.add_argument('--notification', default=os.environ.get('NOTIFICATION', None))
    args = parser.parse_args()
    run(args)
