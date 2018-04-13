#!/usr/bin/env python

# This is intended to consume a stream of quota info from stdin.
# check_quotas.sh can be used to generate the stream.

# Example usage: bash check_quotas.sh | python parse_quotas.py >> /var/log/quotas.log

import sys
import csv
from datetime import datetime

# All known quotas as of 2018-04-13
QUOTAS = [
    'AUTOSCALERS',
    'COMMITMENTS',
    'CPUS',
    'DISKS_TOTAL_GB',
    'INSTANCES',
    'INSTANCE_GROUPS',
    'INSTANCE_GROUP_MANAGERS',
    'INTERNAL_ADDRESSES',
    'IN_USE_ADDRESSES',
    'LOCAL_SSD_TOTAL_GB',
    'NVIDIA_K80_GPUS',
    'NVIDIA_P100_GPUS',
    'NVIDIA_V100_GPUS',
    'PREEMPTIBLE_CPUS',
    'PREEMPTIBLE_LOCAL_SSD_GB',
    'PREEMPTIBLE_NVIDIA_K80_GPUS',
    'PREEMPTIBLE_NVIDIA_P100_GPUS',
    'REGIONAL_AUTOSCALERS',
    'REGIONAL_INSTANCE_GROUP_MANAGERS',
    'SSD_TOTAL_GB',
    'STATIC_ADDRESSES',
]

reader = csv.DictReader(sys.stdin)
name_to_usage = {}
for row in reader:
    name = row['metric']
    name_to_usage[name] = int(float(row['usage']))

usage_list = []
# Iterating over known quotas means we will print exactly this list of quotas in this order,
# even if Google adds new ones (which will get ignored).
for name in QUOTAS:
    if name in name_to_usage:
        usage_list.append(str(name_to_usage[name]))
    else:
        # Protects us in case Google ever renames or stops reporting a quota
        usage_list.append('')

usage_str = '\t'.join(usage_list)
now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

print(now + '\t' + usage_str)
