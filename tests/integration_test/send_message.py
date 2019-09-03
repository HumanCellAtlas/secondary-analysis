import argparse
import base64
import os
import requests


def run(args):
    with open(args.notification) as f:
        contents = f.read().encode('utf-8')
        data = base64.b64encode(contents).decode('utf-8')

    message = {
        'message': {
            'data': data,
            'message_id': '12345'
        }
    }
    response = requests.post(args.lira_submit_url, json=message)
    if response.status_code == 201:
        response_json = response.json()
        workflow_id = response_json['id']
        print(workflow_id)
    else:
        msg = 'Unexpected response code {0} when sending notification {1} to url {2}: \n{3}'
        raise ValueError(
            msg.format(
                response.status_code, args.notification, args.lira_submit_url, response.text
            )
        )

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--lira_submit_url', default=os.environ.get('LIRA_SUBMIT_URL', None))
    parser.add_argument('--notification', default=os.environ.get('NOTIFICATION', None))
    args = parser.parse_args()
    run(args)
