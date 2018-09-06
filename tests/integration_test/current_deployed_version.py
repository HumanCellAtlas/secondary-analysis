#!/usr/bin/env python
"""
Parses the TSV file {mint_deployment_dir}/{env}.tsv and returns
the version from the first line in the column named {component_name}.
For example, given the following TSV:
lira	10x	ss2
0.1.2	1.0.0	2.0.0
0.1.1 0.9.3	1.2.3

If component_name is lira, returns "0.1.2"
If component_name is 10x, returns "1.0.0".
If component_name is ss2, returns "2.0.0".

"""

import argparse
import csv


def run(component_name, mint_deployment_dir, env):
    with open('{0}/{1}.tsv'.format(mint_deployment_dir, env)) as f:
        reader = csv.DictReader(f, delimiter='\t')
        row = reader.next()
        print(row[component_name])


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--component_name', required=True)
    parser.add_argument('--mint_deployment_dir', required=True)
    parser.add_argument('--env', required=True)
    args = parser.parse_args()
    run(args.component_name, args.mint_deployment_dir, args.env)
