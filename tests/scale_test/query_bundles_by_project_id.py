import argparse
import json
import logging
from utils import utils


def format_query(project_uuid, workflow_name):
    es_query_path = utils.SUBSCRIPTION_QUERIES.get(workflow_name)
    if not es_query_path:
        raise ValueError(f'No subscription query available for {workflow_name}.')
    query = utils.load_es_query(es_query_path)
    project_id_query = {'match': {'files.project_json.provenance.document_id': project_uuid}}
    must_match = query['query']['bool']['must']
    must_match.append(project_id_query)
    query['query']['bool']['must'] = must_match
    return {"es_query": query}

def get_dss_url(env):
    if env == 'prod':
        return 'https://dss.data.humancellatlas.org'
    return f'https://dss.{env}.data.humancellatlas.org'

def main(project_uuid, workflow_name, env, output_file_path):
    query = format_query(project_uuid, workflow_name)
    dss_url = get_dss_url(env)
    bundles_list = utils.get_bundles(query, dss_url)
    # TODO: Make sure it's the latest version of the bundles if there is more than one!!!
    if len(bundles_list) == 0:
        raise ValueError(f'No {workflow_name} bundles found for project {project_uuid}')
    with open(output_file_path, 'w') as f:
        json.dump(bundles_list, f, indent=2)


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
