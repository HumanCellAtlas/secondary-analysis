#!/usr/bin/env python

import json
import argparse
import requests
import logging


def prep_json(query_json):
    with open(query_json) as f:
        query = json.load(f)
    return {
        "es_query": query
    }


def get_bundles(query_json, dss_url, output_format, replica):
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
    search_url = '{}/v1/search?output_format={}&replica={}&per_page=500'.format(dss_url.strip('/'), output_format, replica)
    headers = {'Content-type': 'application/json'}
    response = requests.post(search_url, json=query_json, headers=headers)
    results = response.json()['results']
    total_hits = response.json()['total_hits']
    logging.info('{} matching bundles found in {}'.format(total_hits, dss_url))
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


def format_bundle(bundle_fqid):
    bundle_components = bundle_fqid.split('.', 1)
    return {
        'bundle_uuid': bundle_components[0],
        'bundle_version': bundle_components[1]
    }


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser()
    parser.add_argument("dss_url", help='URL for data storage service.')
    parser.add_argument("query_json", help='JSON file containing the query to register.')
    parser.add_argument("--output_format", required=False, default='summary',
                        help=('Format of the query results, either "summary" for a list of UUIDs or "raw" to ' +
                              'include the bundle JSON metadata.'))
    parser.add_argument("--replica", required=False, default='gcp', help='The cloud replica to search in, either "gcp" or "aws".')
    parser.add_argument("--output_file_path", required=False, default="bundles.json", help="Path to output JSON file.")
    args = parser.parse_args()
    es_query = prep_json(args.query_json)
    bundles_list = get_bundles(es_query, args.dss_url, args.output_format, args.replica)
    with open(args.output_file_path, 'w') as f:
        json.dump(bundles_list, f, indent=2)
