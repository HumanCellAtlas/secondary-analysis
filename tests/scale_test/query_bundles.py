#!/usr/bin/env python

import json
import argparse
import logging
from utils import utils

def prep_json(query_json):
    with open(query_json) as f:
        query = json.load(f)
    return {"es_query": query}


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser()
    parser.add_argument("dss_url", help='URL for data storage service.')
    parser.add_argument(
        "query_json", help='JSON file containing the query to register.'
    )
    parser.add_argument(
        "--output_format",
        required=False,
        default='summary',
        help=(
            'Format of the query results, either "summary" for a list of UUIDs or "raw" to '
            + 'include the bundle JSON metadata.'
        ),
    )
    parser.add_argument(
        "--replica",
        required=False,
        default='gcp',
        help='The cloud replica to search in, either "gcp" or "aws".',
    )
    parser.add_argument(
        "--output_file_path",
        required=False,
        default="bundles.json",
        help="Path to output JSON file.",
    )
    args = parser.parse_args()
    es_query = prep_json(args.query_json)
    bundles_list = utils.get_bundles(es_query, args.dss_url, args.output_format, args.replica)
    with open(args.output_file_path, 'w') as f:
        json.dump(bundles_list, f, indent=2)
