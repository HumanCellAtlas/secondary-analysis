#!/usr/bin/env bash

# Prints quota usage to stdout in csv format.

# Usage: bash check_quotas.sh

gcloud compute regions describe us-central1 --flatten='quotas[]' --format='csv(quotas.metric,quotas.limit,quotas.usage)' | python /usr/local/bin/parse_quotas.py >> /var/log/quotas.log
