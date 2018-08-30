#!/usr/bin/env python

import argparse
import json
import requests
import os
from requests_http_signature import HTTPSignatureAuth


def run(args):
    with open(args.notification) as f:
        notification = json.load(f)

    if args.hmac_key:
        auth = HTTPSignatureAuth(key_id=args.hmac_key_id, key=args.hmac_key.encode('utf-8'))
        response = requests.post(args.lira_url, json=notification, auth=auth)
    else:
        token = args.query_param_token
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
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--query_param_token', default=os.environ.get('QUERY_PARAM_TOKEN', None))
    group.add_argument('--hmac_key', default=os.environ.get('HMAC_KEY', None))
    parser.add_argument('--hmac_key_id', default=os.environ.get('HMAC_KEY_ID', None))
    parser.add_argument('--notification', default=os.environ.get('NOTIFICATION', None))
    args = parser.parse_args()

    if args.hmac_key and not args.hmac_key_id:
        parser.error('You must specify hmac_key_id when you specify hmac_key')

    run(args)
