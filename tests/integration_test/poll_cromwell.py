import argparse
import os
import time
from datetime import datetime, timedelta
import cromwell_tools.cromwell_api
import cromwell_tools.cromwell_auth


def run(auth, pubsub_message_id, timeout_minutes=15, poll_interval_seconds=30):
    start = datetime.now()
    timeout = timedelta(minutes=int(timeout_minutes))
    workflow_id = None
    while workflow_id is None:
        if datetime.now() - start > timeout:
            msg = f'No workflow started by message {pubsub_message_id} after {timeout} minutes.'
            raise Exception(msg.format(timeout))

        results = cromwell_tools.cromwell_api.CromwellAPI.query(
            auth=auth,
            query_dict={
                'label': {'pubsub-message-id': pubsub_message_id}
            })

        workflows = results.json()['results']
        print(len(workflows))
        if len(workflows) != 0:
            workflow_id = workflows[0]['id']
            print(workflow_id)
        time.sleep(poll_interval_seconds)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--cromwell_url', default=os.environ.get('CROMWELL_URL', None))
    parser.add_argument('--service_account_key', default=os.environ.get('SERVICE_ACCOUNT_KEY', None))
    parser.add_argument('--pubsub_message_id', default=os.environ.get('PUBSUB_MESSAGE_ID', None))
    args = parser.parse_args()
    cromwell_auth = cromwell_tools.cromwell_auth.CromwellAuth.harmonize_credentials(
        url=args.cromwell_url, service_account_key=args.service_account_key
    )
    run(cromwell_auth, args.pubsub_message_id)
