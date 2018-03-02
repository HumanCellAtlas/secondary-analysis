#!/usr/bin/env python

# This is intended to consume a stream of quota info from stdin.
# check_quotas.sh can be used to generate the stream.

# Example usage: bash check_quotas.sh | python parse_quotas.py >> /var/log/quotas.log

import sys
from datetime import datetime

KEY_QUOTAS = ['CPUS', 'PREEMPTIBLE_CPUS', 'IN_USE_ADDRESSES', 'DISKS_TOTAL_GB']

q = {}
for line in sys.stdin:
    parts = line.strip().split(',')
    name = parts[0]
    if name in KEY_QUOTAS:
        maximum, used = map(int, map(float, parts[1:]))
        q[name] = used

now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
quota_format = '{0}\t{1}\t{2}\t{3}\t{4}'
quota_str = quota_format.format(now, q['CPUS'], q['PREEMPTIBLE_CPUS'], q['IN_USE_ADDRESSES'], q['DISKS_TOTAL_GB'])

print(quota_str)
