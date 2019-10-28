#!/bin/bash

python3 scavenger.py -d "dev" -p "abe1a013-af7a-45ed-8c26-f3793c24a1f4" -c "caas_prod_key_for_dev.json"

python3 scavenger.py -d "integration" -p "abe1a013-af7a-45ed-8c26-f3793c24a1f4" -c "caas_prod_key_for_integration.json"

python3 scavenger.py -d "staging" -p "abe1a013-af7a-45ed-8c26-f3793c24a1f4" -c "caas_prod_key_for_staging.json"

python3 scavenger.py -d "prod" -p "abe1a013-af7a-45ed-8c26-f3793c24a1f4" -c "caas_prod_key_for_prod.json"
