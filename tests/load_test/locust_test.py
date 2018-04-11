#!/usr/bin/env python3

from load_test.models import Payload, locust_agent_factory
from locust import HttpLocust
import json
import logging


try:
    with open('locust.json') as f:
        config = json.load(f)
except (IOError, TypeError):
    logging.critical('Cannot load the locust.json correctly, please double check!')


class UserClass(HttpLocust):
    task_set = locust_agent_factory(payload=config.get('content'), params=config.get('params'), notification_ratio=config.get('notification_ratio'))
    min_wait = 1000
    max_wait = 5000
