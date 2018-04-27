#!/usr/bin/env python

import argparse
import os
import time
from datetime import datetime, timedelta
from cromwell_tools import cromwell_tools

failed_statuses = ['Failed', 'Aborted', 'Aborting']


def run(args):
    workflow_ids = args.workflow_ids.split(',')
    start = datetime.now()
    timeout = timedelta(minutes=int(args.timeout_minutes))
    while True:
        if datetime.now() - start > timeout:
            msg = 'Unfinished workflows after {0} minutes.'
            raise Exception(msg.format(timeout))
        statuses = cromwell_tools.get_workflow_statuses(workflow_ids, args.cromwell_url, args.cromwell_user,
                                                        args.cromwell_password, caas_key=args.caas_key)
        all_succeeded = True
        for i, status in enumerate(statuses):
            if status in failed_statuses:
                raise Exception('Stopping because workflow {0} {1}'.format(workflow_ids[i], status))
            elif status != 'Succeeded':
                all_succeeded = False
        if all_succeeded:
            print('All workflows succeeded!')
            break
        else:
            time.sleep(args.poll_interval_seconds)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--workflow_ids')
    parser.add_argument('--workflow_names')
    parser.add_argument('--cromwell_url')
    parser.add_argument('--cromwell_user', default=os.environ.get('cromwell_user', None))
    parser.add_argument('--cromwell_password', default=os.environ.get('cromwell_password', None))
    parser.add_argument('--caas_key', required=False, help='Service account JSON key for cromwell-as-a-service')
    parser.add_argument('--timeout_minutes')
    parser.add_argument('--poll_interval_seconds', type=int, default=20)
    args = parser.parse_args()
    run(args)
