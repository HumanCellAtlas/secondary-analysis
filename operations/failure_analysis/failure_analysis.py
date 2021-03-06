"""
This script queries cromwell for workflows based on the input parameters (e.g. name, statuses, start, end) and produces
a CSV file listing the following for each:
    - workflow id
    - bundle id
    - status
    - failed task (only for failed or aborted workflows)
    - failure message (only for failed or aborted workflows)

Additionally, this script will create an additional file containing the stderr messages for each failed workflow to
facilitate further analysis if the "record_std_err" parameter is set to true.
"""

import os
import logging
import argparse
import collections
import arrow
import requests
import json
from google.api_core import exceptions as gcs_exceptions
from pipeline_tools import gcs_utils
from cromwell_tools import cromwell_tools

STATUSES = {
    'SUCCEEDED': 'Succeeded',
    'RUNNING': 'Running',
    'FAILED': 'Failed',
    'ABORTED': 'Aborted',
    'DONE': 'Done',
}

ERRORS = {
    'LOCK_EXCEPTION': 'Optimistic lock exception on saving entity',
    'TIMEOUT_STATUS': 'Timed out while waiting for Valid status',
    'BAD_GATEWAY': 'requests.exceptions.HTTPError: 502 Server Error: Bad Gateway',
    'INCOMPLETE_READ': 'httplib.IncompleteRead',
}


def download_gcs_blob(gcs_client, bucket_name, source_blob_name):
    if not gcs_client.storage_client:
        gcs_client.storage_client
    authenticated_gcs_client = gcs_client.storage_client
    bucket = authenticated_gcs_client.bucket(bucket_name)
    blob = bucket.blob(source_blob_name)
    return blob.download_as_string()


def get_gcs_file(gs_link):
    bucket_name, gs_file = gcs_utils.parse_bucket_blob_from_gs_link(gs_link)
    gcs_client = gcs_utils.GoogleCloudStorageClient(
        key_location=os.environ["GOOGLE_APPLICATION_CREDENTIALS"],
        scopes=['https://www.googleapis.com/auth/devstorage.read_only'],
    )
    try:
        result = download_gcs_blob(gcs_client, bucket_name, gs_file)
    except gcs_exceptions.NotFound:
        print('No such file {}'.format(gs_file))
        return
    return result.decode('utf-8')


class Query(object):
    def factory(
        start=None, submission=None, end=None, name=None, statuses=None, labels=None
    ):
        query = collections.namedtuple(
            'Query',
            ['start', 'end', 'name', 'statuses', 'labels', 'submission'],
            verbose=False,
        )
        query.__new__.__defaults__ = (None,) * len(query._fields)
        return query(
            start=local_time(start, 'US/Eastern') if start else None,
            end=local_time(end, 'US/Eastern') if end else None,
            name=name,
            statuses=statuses,
            labels=labels,
        )

    factory = staticmethod(factory)


def query_workflows(
    cromwell_url,
    auth,
    headers,
    start=None,
    submission=None,
    end=None,
    name=None,
    statuses=None,
    labels=None,
):
    query = Query.factory(
        start=local_time(start, 'US/Eastern') if start else None,
        end=local_time(end, 'US/Eastern') if end else None,
        name=name,
        statuses=statuses,
        labels=labels,
        submission=local_time(submission, 'US/Eastern') if submission else None,
    )
    result = requests.post(
        url='{}/query'.format(cromwell_url),
        json=cromwell_query_params(query),
        auth=auth,
        headers=headers,
    )
    result.raise_for_status()
    total_results = result.json()['totalResultsCount']
    logging.info('Total results: {}'.format(str(total_results)))
    result_list_metadata = result.json()['results']
    return result_list_metadata


def cromwell_query_params(query):
    query_params = []
    if query.start:
        start = query.start.to('UTC').strftime('%Y-%m-%dT%H:%M:%S.%fZ')
        query_params.append({'start': start})
    if query.submission:
        submission = query.submission.to('UTC').strftime('%Y-%m-%dT%H:%M:%S.%fZ')
        query_params.append({'submission': submission})
    if query.end:
        end = query.end.to('UTC').strftime('%Y-%m-%dT%H:%M:%S.%fZ')
        query_params.append({'end': end})
    if query.name:
        query_params.append({'name': query.name})
    if query.statuses:
        statuses = [{'status': s} for s in set(query.statuses)]
        query_params.extend(statuses)
    if query.labels:
        statuses = [{'label': l} for l in set(query.labels)]
        query_params.extend(statuses)
    return query_params


def get_metadata(cromwell_url, workflow_id, auth, headers, expand_subworkflows=True):
    metadata_url = '{}/{}/metadata'.format(cromwell_url.strip('/'), workflow_id)
    if expand_subworkflows:
        metadata = requests.get(
            url=metadata_url,
            auth=auth,
            headers=headers,
            params={'expandSubWorkflows': True},
        )
    else:
        metadata = requests.get(url=metadata_url, auth=auth, headers=headers)
    metadata.raise_for_status()
    return metadata.json()


def parse_workflow(workflow_metadata, cromwell_url):
    workflow_id = workflow_metadata['id']
    bundle_id = workflow_metadata['labels']['bundle-uuid']

    parsed_meta = {
        'name': workflow_metadata.get('workflowName'),
        'submission': workflow_metadata.get('submission'),
        'start': workflow_metadata.get('start'),
        'end': workflow_metadata.get('end'),
        'id': workflow_id,
        'status': workflow_metadata['status'],
        'bundle_id': bundle_id,
        'calls': get_tasks(workflow_metadata, workflow_id, bundle_id, cromwell_url),
    }
    return parsed_meta


def get_tasks(metadata, root_workflow_id, bundle_id, cromwell_url=None):
    tasks = []
    calls = metadata.get('calls')
    for task_name in calls:
        task_metadata = calls[task_name][-1]
        if task_metadata.get('subWorkflowMetadata'):
            tasks.extend(
                get_tasks(
                    task_metadata['subWorkflowMetadata'], root_workflow_id, bundle_id
                )
            )
        elif task_metadata.get('subWorkflowId'):
            # If the subworkflow metadata is not embedded in the main workflow metadata, request it separately
            logging.info(
                'Getting metadata for {}'.format(task_metadata.get('subWorkflowId'))
            )
            subworkflow_metadata = get_metadata(
                task_metadata.get('subWorkflowId'), auth, headers, cromwell_url
            )
            tasks.extend(get_tasks(subworkflow_metadata, root_workflow_id, bundle_id))
        else:
            tasks.append(
                parse_task(task_name, task_metadata, root_workflow_id, bundle_id)
            )
    return tasks


def parse_task(task_name, task_metadata, root_workflow_id, bundle_id):
    return {
        'root_workflow_id': root_workflow_id,
        'name': task_name,
        'start': task_metadata['start'],
        'end': task_metadata.get('end'),
        'status': task_metadata['executionStatus'],
        'failures': task_metadata.get('failures'),
        'attempt': task_metadata['attempt'],
        'stdout': task_metadata.get('stdout'),
        'stderr': task_metadata.get('stderr'),
        'bundle_id': bundle_id,
    }


def local_time(time_string, time_zone='US/Eastern'):
    return arrow.get(time_string).replace(tzinfo=time_zone)


def find_duplicate_bundle_ids(bundle_ids):
    unique_bundle_ids = set(bundle_ids)
    logging.info(
        '{} unique bundles out of {} total'.format(
            str(len(set(bundle_ids))), str(len(bundle_ids))
        )
    )

    # Duplicate bundles
    bundle_count = {}
    for _id in unique_bundle_ids:
        bundle_count[_id] = 0
    for _id in bundle_ids:
        bundle_count[_id] += 1
    duplicate_bundles = {}
    for _id in bundle_count:
        if bundle_count[_id] > 1:
            duplicate_bundles[_id] = bundle_count[_id]
    duplicate_bundles_list = duplicate_bundles.keys()
    logging.info(
        '{} duplicate bundles: {}'.format(
            str(len(duplicate_bundles_list)), list(duplicate_bundles_list)
        )
    )
    return duplicate_bundles


def sort_workflows_by_status(workflows):
    summary = collections.defaultdict(list)
    for workflow in workflows:
        status = workflow['status']
        summary[status].append(workflow)
    return summary


def group_workflows_by_failed_task(workflows):
    workflows_by_task = collections.defaultdict(list)
    for workflow in workflows:
        for task in workflow.get('calls'):
            if (
                task['status'] == STATUSES['FAILED']
                or task['status'] == STATUSES['ABORTED']
            ):
                workflows_by_task[task['name']].append(task)
    for task_name in workflows_by_task.keys():
        logging.info('{}: {}'.format(task_name, len(workflows_by_task[task_name])))
    return workflows_by_task


def get_failure_message(task_metadata, record_std_err=True):
    failure_message = json.dumps(task_metadata.get('failures'))
    stderr_link = task_metadata.get('stderr')
    if stderr_link:
        file_contents = get_gcs_file(stderr_link)
        if file_contents:
            for error in ERRORS:
                if ERRORS[error] in file_contents:
                    failure_message = ERRORS[error]
                    break
            else:
                if record_std_err:
                    # Record the full std error for any exception that is not found in the `ERRORS` dict
                    print('Unknown exception, recording std error...')
                    with open('std_err.txt', 'a') as f:
                        f.write(file_contents + '\n\n')
    return failure_message


def format_metadata_output(metadata, record_std_err):
    status = metadata.get('status')
    data = {
        'bundle_id': metadata['bundle_id'],
        'id': metadata.get('root_workflow_id') or metadata['id'],
        'status': status,
        'task_name': metadata.get('name', '')
        if status == STATUSES['FAILED'] or status == STATUSES['ABORTED']
        else '',
        'error': get_failure_message(metadata, record_std_err)
        if status == STATUSES['FAILED']
        else '',
    }
    return data


def main(
    cromwell_url,
    auth,
    headers,
    output_file,
    record_std_err=True,
    start=None,
    submission=None,
    end=None,
    name=None,
    statuses=None,
    labels=None,
    expand_subworkflows=True,
):
    # Get target workflows
    result_list_metadata = query_workflows(
        cromwell_url, auth, headers, start, submission, end, name, statuses, labels
    )

    # Get workflow metadata
    result_ids = [workflow['id'] for workflow in result_list_metadata]
    logging.info('Retrieving Adapter Workflows\' Metadata: ')
    adapter_metadata = []
    for idx, workflow_id in enumerate(result_ids):
        logging.info(
            'Current {0}/{1}: {2}'.format(idx + 1, len(result_ids), workflow_id)
        )
        workflow_metadata = get_metadata(
            cromwell_url,
            workflow_id,
            auth,
            headers,
            expand_subworkflows=expand_subworkflows,
        )
        adapter_metadata.append(workflow_metadata)
    adapter_metrics = [
        parse_workflow(workflow_metadata, cromwell_url)
        for workflow_metadata in adapter_metadata
    ]

    # Check for duplicate bundles
    total_bundle_ids = [wf['bundle_id'] for wf in adapter_metrics]
    find_duplicate_bundle_ids(total_bundle_ids)

    # Group workflows by status
    summary = sort_workflows_by_status(adapter_metrics)
    for status in summary.keys():
        workflow_count = len(summary[status])
        message = '{}: {}'.format(status, str(workflow_count))
        if status == STATUSES['SUCCEEDED']:
            bundle_ids = [wf['bundle_id'] for wf in summary[status]]
            message += ' ({} unique bundles)'.format(str(len(set(bundle_ids))))
        logging.info(message)

    workflow_data = []
    for status in summary.keys():
        if status != STATUSES['FAILED'] and status != STATUSES['ABORTED']:
            workflow_data.extend(
                [format_metadata_output(w, record_std_err) for w in summary[status]]
            )

    # Find failed tasks
    failed_workflows = summary[STATUSES['FAILED']]
    failed_tasks = group_workflows_by_failed_task(failed_workflows)
    for task_name in failed_tasks:
        workflow_data.extend(
            [
                format_metadata_output(task, record_std_err)
                for task in failed_tasks[task_name]
            ]
        )

    # Find last task of aborted workflows
    aborted_workflows = summary[STATUSES['ABORTED']]
    aborted_tasks = group_workflows_by_failed_task(aborted_workflows)
    for task_name in aborted_tasks:
        workflow_data.extend(
            [
                format_metadata_output(task, record_std_err)
                for task in failed_tasks[task_name]
            ]
        )

    with open(output_file, 'w') as f:
        f.write(
            'Primary Bundle ID,Workflow ID,Workflow Status,Failed Task,Workflow Error\n'
        )
        for each in workflow_data:
            f.write(
                '{},{},{},{},{}\n'.format(
                    each.get('bundle_id'),
                    each.get('id'),
                    each.get('status'),
                    each.get('task_name'),
                    each.get('error', ''),
                )
            )


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--cromwell_url',
        default='https://cromwell.caas-prod.broadinstitute.org/api/workflows/v1',
        help='Cromwell API URL',
    )
    parser.add_argument(
        '--cromwell_user',
        required=False,
        help='Username for the specified Cromwell url',
    )
    parser.add_argument(
        '--cromwell_password',
        required=False,
        help='Password for the specified Cromwell url',
    )
    parser.add_argument(
        '--caas_key',
        required=False,
        help='Path to a service account JSON key for Cromwell-as-a-Service',
    )
    parser.add_argument(
        '--bucket_reader_key',
        required=True,
        help='Path to a service account JSON key for reading from the gcloud workflow execution bucket',
    )
    parser.add_argument(
        '--output_file',
        default='workflow_failures.csv',
        help='Path to the output CSV file',
    )
    parser.add_argument('--start', required=False, help='Start time to query by')
    parser.add_argument(
        '--submission', required=False, help='Submission time to query by'
    )
    parser.add_argument('--end', required=False, help='End time to query by')
    parser.add_argument('--name', required=False, help='Workflow name to query by')
    parser.add_argument(
        '--statuses', nargs='+', required=False, help='Workflow statuses to query by'
    )
    parser.add_argument(
        '--labels',
        nargs='+',
        required=False,
        help='Workflow labels to query by, in the format key:value',
    )
    parser.add_argument(
        '--expand_subworkflows',
        default=True,
        help='Whether to include subworkflow metadata in the Cromwell metadata',
    )
    parser.add_argument(
        '--record_std_err',
        default=True,
        help="Whether to save the stderr messages from the failed workflows to a file",
    )
    args = parser.parse_args()
    os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = args.bucket_reader_key
    auth, headers = cromwell_tools._get_auth_credentials(
        cromwell_user=args.cromwell_user,
        cromwell_password=args.cromwell_password,
        caas_key=args.caas_key,
    )
    main(
        args.cromwell_url,
        auth,
        headers,
        args.output_file,
        args.record_std_err,
        args.start,
        args.submission,
        args.end,
        args.name,
        args.statuses,
        args.labels,
        args.expand_subworkflows,
    )
