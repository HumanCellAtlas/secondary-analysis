#!/usr/bin/env python3
from load_test.models import Payload, OrdinaryLoadTestAgent
from pathlib import Path
import time
import click


@click.command()
@click.option('--counts', default=1, help='Number of notifications.')
@click.option('--url', help='The url to the endpoint of Lira you want to test aginst. e.g http://pipelines.dev.data.humancellatlas.org/notifications')
@click.option('--auth_token', help='The value of auth token to the Lira, could be set to False to disable it.')
@click.option('--payload_file', help='Path to the notification file. e.g. ./data/notification/notification.json')
@click.option('--result_folder', help='Path to the result folder. e.g. ./data/results/')
@click.option('--lira_version', help='The version of Lira to be tested against. e.g. v0.7.0')
@click.option('--environment', help='The running environment of Lira. gunicorn/docker/gke')
@click.option('--mode', help='The running mode of Lira, dry_run/live_run')
@click.option('--cromwell_type', help='The type of Cromwell which the Lira is connecting to. null/instance/caas')
@click.option('--caching', help='The caching switch of Lira. True/False')
def normal_loadtest(counts, url, auth_token, payload_file, result_folder, lira_version, environment, mode,
                    cromwell_type, caching):
    destination = Path(result_folder) / 'load_test_result_{}.json'.format(time.strftime("%Y%m%d-%H%M%S"))
    scenario = {
        'lira': lira_version,
        'environment': environment,
        'mode': mode,
        'cromwell': cromwell_type,
        'caching': caching,
    }

    if auth_token:
        auth_token = {'auth': auth_token}
    else:
        auth_token = None
    # FIXME: Using https in url here will run into a "RecursionError: maximum recursion depth exceeded" bug of requests
    payload = Payload(url=url, content=Path(payload_file), params=auth_token)
    agent = OrdinaryLoadTestAgent(payload=payload, scenario=scenario, counts=counts)

    agent.run()
    agent.dump_metrics(destination)


if __name__ == '__main__':
    normal_loadtest()
