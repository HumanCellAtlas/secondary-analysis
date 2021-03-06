"""This script helps remove the intermediate execution files generated by
Cromwell execution engine."""
from cromwell_tools.cromwell_auth import CromwellAuth
from cromwell_tools import api
from google.cloud import storage
import argparse
from tqdm import tqdm
import sys


EXECUTION_BUCKETS = {
    'dev': 'broad-dsde-mint-dev-cromwell-execution',
    'integration': 'broad-dsde-mint-integration-cromwell-execution',
    'staging': 'broad-dsde-mint-staging-cromwell-execution',
    'prod': 'hca-dcp-pipelines-prod-cromwell-execution',
}


def get_workflows(query_dict: dict, auth: 'CromwellAuth') -> list:
    "Query workflows by query_dict."
    response = api.query(query_dict=query_dict, auth=auth, raise_for_status=True)
    return response.json()['results']


def mark_workflow(workflow: dict, auth: 'CromwellAuth'):
    "Mark the workflow with 'erased'."
    api.patch_labels(uuid=workflow['id'], labels={'comment': 'erased'}, auth=auth)


def compose_gs_path(workflow: dict, deployment: str) -> str:
    "Compose the path to the blob which needs to be erased."
    gs_path = f"caas-cromwell-executions/{workflow['name']}/{workflow['id']}"
    return gs_path


def delete_blob(workflow: dict, deployment: str, storage_client: storage.Client) -> str:
    "Delete the blob."
    print(f"Deleting execution files for workflow: {workflow['id']}")
    bucket = storage_client.get_bucket(EXECUTION_BUCKETS[deployment])
    gs_path = compose_gs_path(workflow=workflow, deployment=deployment)
    blobs = bucket.list_blobs(prefix=gs_path)
    print(f"\tDeleting execution files under: {gs_path}")
    bucket.delete_blobs(blobs=blobs)
    print("Done!")


def run(deployment: str, project: str, service_account_key: str):
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
        }
    }

    target_workflows = get_workflows(query_dict=query_dict, auth=auth)

    # initialize the storage client only once per invocation
    gs_storage_client = storage.Client()

    # delete files workflow by workflow
    for target_workflow in tqdm(target_workflows):
        try:
            delete_blob(
                workflow=target_workflow,
                deployment=deployment,
                storage_client=gs_storage_client,
            )
        except Exception as e:
            print(e)
            print(
                f"An error occurred when deleting execution files for: {target_workflow['id']}"
            )
            continue
        mark_workflow(workflow=target_workflow, auth=auth)


class DefaultHelpParser(argparse.ArgumentParser):
    def error(self, message):
        sys.stderr.write('error: %s\n' % message)
        self.print_help()
        sys.exit(2)


if __name__ == '__main__':
    parser = DefaultHelpParser(
        description='Command Line Interface for removing files from Cromwell Execution locations.',
        prog='scavenger',
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
    args = parser.parse_args()
    run(
        deployment=args.deployment,
        project=args.project,
        service_account_key=args.service_account_key,
    )
