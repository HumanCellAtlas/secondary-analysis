"""This script gets the diff between the bundles that are supposed to
trigger workflows and the bundles that indeed triggered workflows. This
diff list is helpful when debugging the issues happen between DCP
Data Store, Lira and Lira's (Pub/Sub) queue."""
from cromwell_tools.cromwell_auth import CromwellAuth
from cromwell_tools import api
import argparse
from pathlib import Path
import time
from copy import deepcopy
import json
import requests
import sys


DSS_PRIMARY_BUNDLES_QUERY = {
    "es_query": {
        "query": {
            "bool": {
                "must": [{"match": None}],
                "must_not": [
                    {"match": {"files.analysis_process_json.type.text": "analysis"}}
                ],
            }
        }
    }
}


def get_workflows(query_dict: dict, auth: 'CromwellAuth') -> list:
    "Query workflows by query_dict."
    response = api.query(query_dict=query_dict, auth=auth, raise_for_status=True)
    return response.json()['results']


def get_bundle_uuid_from_workflow_label(workflow: dict) -> str:
    "Get the bundle UUID from the workflow label."
    bundle_uuid = workflow['labels']['bundle-uuid']
    return bundle_uuid


def format_bundle(bundle_fqid: str) -> dict:
    bundle_components = bundle_fqid.split('.', 1)
    return {'bundle_uuid': bundle_components[0], 'bundle_version': bundle_components[1]}


def get_bundles(query_json, dss_url, output_format='summary', replica='gcp'):
    """ Search for bundles in the HCA Data Storage Service using an elasticsearch query.

    Args:
        query_json (dict): Elasticsearch JSON query.
        dss_url (str): URL for the HCA Data Storage Service.
        output_format (str): Format of the query results, either "summary" for a list of UUIDs or "raw" to include'
            the bundle JSON metadata.
        replica (str): The cloud replica to search in, either "gcp" or "aws".

    Returns:
        list: List of dicts in the format { bundle_uuid: <uuid>, bundle_version: <version> }

    """
    dss_url = dss_url.strip('/')
    search_url = f'{dss_url}/v1/search?output_format={output_format}&replica={replica}&per_page=500'
    headers = {'Content-type': 'application/json'}
    response = requests.post(search_url, json=query_json, headers=headers)
    results = response.json()['results']
    total_hits = response.json()['total_hits']
    bundles = [format_bundle(r['bundle_fqid']) for r in results]

    # The 'link' header refers to the next page of results to fetch. If there is no link header present,
    # all results have been fetched.
    # Example:
    # link: <https://dss.dev.data.humancellatlas.org/v1/search?output_format=summary&replica=gcs&per_page=500&scroll_id=123>; rel="next"
    link_header = response.headers.get('link', None)
    while link_header:
        next_link = link_header.split(';')[0]
        next_url = next_link.strip('<').strip('>')
        response = requests.post(next_url, json=query_json, headers=headers)
        results = response.json()['results']
        bundles.extend(format_bundle(r['bundle_fqid']) for r in results)
        link_header = response.headers.get('link', None)
    return bundles


def query_dss_by_project_uuid(project_uuid: str, deployment: str) -> list:
    """Query DSS to get the bundle list by project_uuid."""
    query = deepcopy(DSS_PRIMARY_BUNDLES_QUERY)
    query['es_query']['query']['bool']['must'][0]['match'] = {
        "files.project_json.provenance.document_id": project_uuid
    }
    dss_url = (
        'https://dss.data.humancellatlas.org'
        if deployment == 'prod'
        else f'https://dss.{deployment}.data.humancellatlas.org'
    )
    bundles_in_dss = get_bundles(query_json=query, dss_url=dss_url)
    uuids = list(set([b['bundle_uuid'] for b in bundles_in_dss]))
    return uuids


def run(deployment: str, project: str, service_account_key: str, output: str):
    # authenticate with Cromwell using OAuth (service account JSON key file)
    auth = CromwellAuth.harmonize_credentials(
        service_account_key=service_account_key,
        url='https://cromwell.caas-prod.broadinstitute.org',
    )

    # query for workflows by project_uuid
    query_dict = {
        'label': {
            'project_uuid': project,
            'caas-collection-name': f'lira-{"int" if deployment == "integration" else deployment}',
        },
        'additionalQueryResultFields': ['labels'],
    }

    target_workflows = get_workflows(query_dict=query_dict, auth=auth)
    uuids_triggered_workflows = [
        get_bundle_uuid_from_workflow_label(workflow=wf) for wf in target_workflows
    ]

    print(f"Found {len(uuids_triggered_workflows)} bundles from workflows.")

    uuids_in_dss = query_dss_by_project_uuid(
        project_uuid=project, deployment=deployment
    )

    bundles_diff = set(uuids_in_dss) - set(uuids_triggered_workflows)

    print(f"Found {len(uuids_in_dss)} bundles in DSS.")

    print(
        f'Found {len(bundles_diff)} bundles that in DSS but did not trigger workflows'
    )

    results = {
        'bundles_in_dss': uuids_in_dss,
        'bundles_triggered_workflows': uuids_triggered_workflows,
        'diff': list(bundles_diff),
    }

    with Path(output).expanduser().resolve().open('w') as f:
        json.dump(results, f)
    print(f'Saved the results to {output}')


class DefaultHelpParser(argparse.ArgumentParser):
    def error(self, message):
        sys.stderr.write('error: %s\n' % message)
        self.print_help()
        sys.exit(2)


if __name__ == '__main__':
    parser = DefaultHelpParser(
        description='Command Line Interface for debugging inconsistent bundles for projects.',
        prog='bundle diff debugger',
    )
    parser.add_argument(
        '-d',
        '--deployment',
        type=str,
        dest='deployment',
        metavar='',
        required=True,
        help='The deployment from {dev, staging, integration, prod}.',
    )
    parser.add_argument(
        '-p',
        '--project',
        type=str,
        dest='project',
        metavar='',
        required=True,
        help='The HCA DCP project UUID you want to remove from the execution buckets.',
    )
    parser.add_argument(
        '-c',
        '--creds',
        type=str,
        dest='service_account_key',
        metavar='',
        required=True,
        help='Path to the JSON key file for authenticating with CaaS.',
    )
    parser.add_argument(
        '-o',
        '--output_file_path',
        type=str,
        dest='output',
        metavar='',
        required=False,
        default=f'bundlelist-{time.strftime("%Y%m%d-%H%M%S")}.json',
        help='The path and name of the output bundle list file. [default: current_timestamp.json]',
    )
    args = parser.parse_args()
    run(
        deployment=args.deployment,
        project=args.project,
        service_account_key=args.service_account_key,
        output=args.output,
    )
