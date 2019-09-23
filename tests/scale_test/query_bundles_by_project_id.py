import argparse
import json
import logging
from datetime import datetime
from utils import utils


def format_query(project_uuid, workflow_name):
    es_query_path = utils.SUBSCRIPTION_QUERIES.get(workflow_name)
    if not es_query_path:
        raise ValueError(f'No subscription query available for {workflow_name}.')
    query = utils.load_es_query(es_query_path)
    project_id_query = {'match': {'files.project_json.provenance.document_id': project_uuid}}
    query['query']['bool']['must'].append(project_id_query)
    return {"es_query": query}

def get_dss_url(env):
    if env == 'prod':
        return 'https://dss.data.humancellatlas.org'
    return f'https://dss.{env}.data.humancellatlas.org'

def get_bundle_datetime(bundle_version):
    return datetime.strptime(bundle_version, '%Y-%m-%dT%H%M%S.%fZ')

def get_latest_bundle_versions(bundle_list):
    bundle_ids = [b['bundle_uuid'] for b in bundle_list]
    if len(bundle_ids) == len(set(bundle_ids)):
        return bundle_list
    else:
        bundle_map = {}
        for each in bundle_list:
            bundle_uuid = each['bundle_uuid']
            bundle_version = each['bundle_version']
            if bundle_uuid in bundle_map:
                existing_version = bundle_map['bundle_uuid']['bundle_version']
                if get_bundle_datetime(bundle_version) > get_bundle_datetime(existing_version):
                    bundle_map[bundle_uuid] = each
            else:
                bundle_map[bundle_uuid] = each
        return bundle_map.values()

def main(project_uuid, workflow_name, env, output_file_path):
    query = format_query(project_uuid, workflow_name)
    dss_url = get_dss_url(env)
    bundles_list = utils.get_bundles(query, dss_url)
    if len(bundles_list) == 0:
        raise ValueError(f'No {workflow_name} bundles found for project {project_uuid}')

    # Check for multiple versions of the same bundle and only return the newest
    latest_bundles = get_latest_bundle_versions(bundles_list)
    with open(output_file_path, 'w') as f:
        json.dump(latest_bundles, f, indent=2)


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser()
    parser.add_argument('project_uuid', help='Unique ID of the project')
    parser.add_argument('workflow_name', help='Name of the analysis pipeline to run')
    parser.add_argument('env', help='Deployment environment containing the project')
    parser.add_argument('--output_file_path', default='project_bundles.json', help='Path of the file to save the search results')
    args = parser.parse_args()
    main(project_uuid=args.project_uuid,
         workflow_name=args.workflow_name,
         env=args.env,
         output_file_path=args.output_file_path)
