#!/usr/bin/env python3
"""A script to send notifications to Lira.

This script provides a set of actions to send notifications to a typical Lira instance
(https://github.com/HumanCellAtlas/lira). In order to use this script, you should have Click and tqdm pre-installed,
check requirements.txt for details.

This script comes with a set of elaborate help messages, you can either leave the command without arguments, or
explicitly use '--help' to check the usages.

Notes:

    This script implements the following functionalities:
    =====================================================
    1. Send a notification to a given Lira from given bundle_uuid and bundle_version.
    2. Send a batch of notifications to a given Lira from a JSON file of bundle list.
    3. Add custom labels to notifications.
    4. Save metrics to a file in batch mode, print to console in single mode.
    5. Switch between single-thread and multi-thread in batch mode.
    6. Check auth_token provided by user.

    CLI definition
    ==============
    In order to pass/carry over the context from the parent command group to nested sub-commands,
     you have to create either a class or a data structure to store the parent parameters/info, and pass it into the
     CLI's main function. This script is currently using a empty dict {} here,
     but it could have been list or even custom class.


Examples:
    Check usage of the script
    -------------------------

        $ python notifier.py notify

        Usage: notifier.py notify [OPTIONS] COMMAND [ARGS]...

        Options:
          --lira_url TEXT       The url to a Lira instance.  [default: https://pipelines.dev.data.humancellatlas.org/]
          --label TEXT          The label to be added to the workflows from notifications. Note: the label should comply with
                                the Cromwell's rules!!  [default: '{"comment": "scaling-test-$(current-date)"}']
          --es_query_path TEXT  The path to the ES query json file which is used for making subscription in BlueBox.
                                [default: ./subscription_queries/smartseq2-query.json]
          --save_path TEXT      The path to the folder to save metrics of this notifier.  [default: ./]
          --help                Show this message and exit.

        Commands:
          batch  Send notifications from a file of a list of bundle UUIDs and VERSIONs.
          once   Send one notification from a given bundle UUID and bundle VERSION.

    To send only one notification
    -----------------------------

        $ python notifier.py notify once

        Usage: notifier.py notify once [OPTIONS]

        Options:
          --uuid TEXT     A bundle UUID in Blue Box.
          --version TEXT  A bundle VERSION matches the UUID in Blue Box
          --help          Show this message and exit.

    To send multiple notifications from a file of bundles
    -----------------------------------------------------

        $ python notifier.py notify batch

        Usage: notifier.py notify batch [OPTIONS]

        Options:
          --bundle_list_file PATH  The path to the file of a list of bundles
          --async                  Asynchronously send notifications, faster.  [default: True]
          --sync                   Synchronously send notifications, linear and slower.  [default: False]
          --help                   Show this message and exit.

    Note: For this batch mode, you could also specify whether to use multi-threading of not. By default, multi-threading
        is enabled. It will send notifications asynchronously, which is much faster. Besides, for the file to be passed
        into this command, it need to be in the following JSON schema:
        [
            {"bundle_uuid": XXX, "bundle_version": XXX},
            {"bundle_uuid": XXX, "bundle_version": XXX}
        ]

"""
import click
import logging
from tqdm import tqdm
import time
from utils import utils
from collections import deque
import concurrent.futures
import functools
import timeit
import pathlib

logging.basicConfig(level=logging.INFO)


@click.group()
def cli():
    pass


@cli.group(context_settings=dict(max_content_width=120))
@click.option('--lira_url',
              default='https://pipelines.dev.data.humancellatlas.org/',
              help='The url to a Lira instance.',
              show_default=True)
@click.option('--label',
              default='{' + str('"comment": "scaling-test-{}"'.format(time.strftime('%Y-%m-%d'))) + '}',
              help='The label to be added to the workflows from notifications. '
                   'Note: the label should comply with the Cromwell\'s rules!!',
              show_default=True)
@click.option('--es_query_path',
              default='./subscription_queries/smartseq2-query.json',
              help='The path to the ES query json file which is used for making subscription in BlueBox.',
              show_default=True)
@click.option('--save_path',
              default='./',
              help='The path to the folder to save metrics of this notifier.',
              show_default=True)
@click.pass_context
def notify(ctx, lira_url, label, es_query_path, save_path):
    ctx.obj['lira_url'] = utils.harmonize_url(lira_url)
    ctx.obj['label'] = utils.compose_label(label)
    ctx.obj['save_path'] = save_path
    ctx.obj['es_query_path'] = es_query_path


@notify.command(short_help='Send one notification from a given bundle UUID and bundle VERSION.')
@click.pass_context
@click.option('--uuid',
              help='A bundle UUID in Blue Box.')
@click.option('--version',
              help='A bundle VERSION matches the UUID in Blue Box')
def once(ctx, uuid, version):
    # Start the timer
    start = timeit.default_timer()

    # Using a custom checker instead of the required=True flag of Click, so it shows the help text
    utils.required_checker(ctx, uuid=uuid, version=version)

    # Checking if the auth_token given is correct
    auth_token = utils.auth_checker(ctx)

    # Prepare arguments
    lira_url, label, es_query_path = ctx.obj['lira_url'], ctx.obj['label'], ctx.obj['es_query_path']

    # Use a probe to get the current subscription_id
    subscription_id = utils.subscription_probe(lira_url)
    logging.info('Using subscription_id: {}'.format(subscription_id))

    # Prepare
    notification = utils.prepare_notification(bundle_uuid=uuid,
                                              bundle_version=version,
                                              es_query_path=es_query_path,
                                              subscription_id=subscription_id,
                                              label=label)

    # Send notifications
    response = utils.send_notification(lira_url, auth_token, notification)

    # Stop the timer
    stop = timeit.default_timer()

    # Output metrics
    logging.info('Sent notification with in {total_time} seconds, status is {status}, Round-Trip-Time is {rtt},'.format(
        total_time=stop - start,
        status=response.status_code,
        rtt=response.elapsed.total_seconds()
    ))


@notify.command(short_help='Send notifications from a file of a list of bundle UUIDs and VERSIONs.')
@click.pass_context
@click.option('--bundle_list_file',
              help='The path to the file of a list of bundles',
              type=click.Path(exists=True))
@click.option('--async',
              'run_mode',
              flag_value='async',
              default=True,
              help='Asynchronously send notifications, faster.',
              show_default=True)
@click.option('--sync',
              'run_mode',
              flag_value='sync',
              help='Synchronously send notifications, linear and slower.',
              show_default=True)
def batch(ctx, bundle_list_file, run_mode):
    # Using a custom checker instead of the required=True flag of Click, so it shows the help text
    utils.required_checker(ctx, file=bundle_list_file)

    # Checking if the auth_token given is correct
    auth_token = utils.auth_checker(ctx)

    # Prepare arguments
    bundles = utils.read_bundles(bundle_list_file)
    lira_url, label, save_path, es_query_path = \
        ctx.obj['lira_url'], ctx.obj['label'], ctx.obj['save_path'], ctx.obj['es_query_path']

    if run_mode == 'async':
        logging.info('Sending notifications asynchronously...\n')
        async_notify(bundles, lira_url, label, es_query_path, auth_token, save_path)
    elif run_mode == 'sync':
        logging.info('Sending notifications synchronously...\n')
        linear_notify(bundles, lira_url, label, es_query_path, auth_token, save_path)


def linear_notify(bundles, lira_url, label, es_query_path, auth_token, save_path):
    # Start the timer
    start = timeit.default_timer()

    # Use a probe to get the current subscription_id
    subscription_id = utils.subscription_probe(lira_url)
    logging.info('Using subscription_id: {}'.format(subscription_id))

    # Prepare the payload
    queue = deque([])
    for bundle in bundles:
        queue.append(
            utils.prepare_notification(bundle_uuid=bundle['bundle_uuid'],
                                       bundle_version=bundle['bundle_version'],
                                       es_query_path=es_query_path,
                                       subscription_id=subscription_id,
                                       label=label))

    # Send notifications
    responses = [utils.send_notification(lira_url, auth_token, notification) for notification in tqdm(queue)]

    # Stop the timer
    stop = timeit.default_timer()

    # Save metrics
    rtt = [response.elapsed.total_seconds() for response in responses]
    status = [response.status_code for response in responses]
    total_time = stop - start
    save_file = pathlib.Path(save_path) / 'notifier_metrics_{}.json'.format(time.strftime("%Y%m%d-%H%M%S"))
    utils.dump_metrics(save_file, rtt=rtt, status=status, total_time=total_time)

    logging.info('Saved the metrics file to {}'.format(save_file))


def async_notify(bundles, lira_url, label, es_query_path, auth_token, save_path):
    # Start the timer
    start = timeit.default_timer()

    # Use a probe to get the current subscription_id
    subscription_id = utils.subscription_probe(lira_url)
    logging.info('Using subscription_id: {}'.format(subscription_id))

    # Prepare the payload
    queue = deque([])
    for bundle in bundles:
        queue.append(
            utils.prepare_notification(bundle_uuid=bundle['bundle_uuid'],
                                       bundle_version=bundle['bundle_version'],
                                       es_query_path=es_query_path,
                                       subscription_id=subscription_id,
                                       label=label))

    # Send notifications
    partial_send_notification = functools.partial(utils.send_notification, lira_url, auth_token)

    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as executor:
        responses = deque(executor.map(partial_send_notification, queue))

    # Stop the timer
    stop = timeit.default_timer()

    # Save metrics
    rtt = [response.elapsed.total_seconds() for response in responses]
    status = [response.status_code for response in responses]
    total_time = stop - start
    save_file = pathlib.Path(save_path) / 'notifier_metrics_{}.json'.format(time.strftime("%Y%m%d-%H%M%S"))
    utils.dump_metrics(save_file, rtt=rtt, status=status, total_time=total_time)

    logging.info('Saved the metrics file to {}'.format(save_file))


if __name__ == '__main__':
    cli(obj={})
