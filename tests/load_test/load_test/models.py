import logging
import json
from locust import TaskSet, task
# requests must be imported after locust or the test will run into an error, according to
# https://github.com/gevent/gevent/issues/941
import requests
import urllib3
from collections import deque
import sys
import time
import datetime
import statistics
from pathlib import PosixPath
from tqdm import tqdm


class Payload(object):
    """Payload class for storing information such as payload data and target url."""
    def __init__(self, url, content, params):
        self.__url = url

        if isinstance(content, str) or isinstance(content, PosixPath):
            self.__content = self._to_dict(content)
        else:
            self.__content = content

        self.__size = sys.getsizeof(self.content)

        if isinstance(params, str) or isinstance(params, PosixPath):
            self.__params = self._to_dict(params)
        else:
            self.__params = params

    def __sizeof__(self):
        return sys.getsizeof(self.content)

    def __repr__(self):
        return json.dumps(self.content)

    def __eq__(self, other):
        return isinstance(other, Payload) and self.content == other.content

    @property
    def url(self):
        return self.__url

    @url.setter
    def url(self, value):
        self.__url = value

    @property
    def content(self):
        return self.__content

    @content.setter
    def content(self, value):
        self.__content = value

    @property
    def params(self):
        return self.__params

    @params.setter
    def params(self, value):
        self.__params = value

    @property
    def size(self):
        return self.__sizeof__()

    @staticmethod
    def _to_dict(path, default_key='data'):
        content = {default_key: ''}
        try:
            with open(path) as file:
                content = json.load(file)
        except (IOError, TypeError):
            logging.warning('Failed to load payload from file, using the default {0} now.'.format(content))
        finally:
            return content


class OrdinaryLoadTestAgent(object):
    """An ordinary class to perform sequential load testing."""
    def __init__(self, payload, scenario, counts=1, interval=0):
        if isinstance(payload, Payload):
            self.payload = payload
        else:
            raise TypeError('Not a valid Payload instance!')
        self.counts = counts
        self.interval = interval if isinstance(interval, int) else 0
        self.response_pool = deque()
        self.__metrics = {
            'metadata': {
                'lira': scenario.get('lira'),
                'environment': scenario.get('environment'),
                'mode': scenario.get('mode'),
                'cromwell': scenario.get('cromwell'),
                'caching': scenario.get('caching'),
                'start_time': str(datetime.datetime.now()),
                'end_time': None,
            },
            'metrics': {
                'notifications_counts': self.counts,
                'successful_notifications': None,
                'notification_bytes_size': self.payload.size,
                'rtt': None,
                'avg_rtt': None,
                'users': 1,
                'interval': self.interval,
            },
            'data': {
                'responses': None,
                'rtt': None,
            },
        }

    @property
    def metrics(self):
        return self.__metrics

    def send_notifications(self):
        if self.payload.params:
            if self.interval:
                time.sleep(self.interval)
            response = requests.post(url=self.payload.url, params=self.payload.params, json=self.payload.content)
        else:
            response = requests.post(url=self.payload.url, json=self.payload.content)
        return response

    def save_responses(self, response):
        data = {
            'id': None,
            'rtt': response.elapsed.total_seconds()
        }
        if response.ok:
            data['id'] = response.json().get('id')
        self.response_pool.append(data)

    def save_metrics(self):
        rtts = [dic.get('rtt') for dic in self.response_pool]

        self.metrics['metrics']['successful_notifications'] = len(rtts)
        self.metrics['metrics']['rtt'] = sum(rtts)
        self.metrics['metrics']['avg_rtt'] = statistics.mean(rtts)
        self.metrics['data']['rtt'] = rtts
        self.metrics['data']['responses'] = [dic.get('id') for dic in self.response_pool]
        self.metrics['metadata']['end_time'] = str(datetime.datetime.now())

    def run(self):
        try:
            probe = self.send_notifications().status_code
            if probe == '405':
                raise ValueError('Payload\'s Auth token is invalid!')
        except (ConnectionRefusedError,
                requests.exceptions.RequestException,
                urllib3.exceptions.NewConnectionError,
                requests.exceptions.ConnectionError) as err:
            logging.critical(err)
            raise requests.exceptions.HTTPError('Failed to connect to {}!'.format(self.payload.url))

        try:
            for count in tqdm(range(self.counts)):
                self.save_responses(self.send_notifications())
        except:  # Intentionally using broad catch here to consider any exceptions, such as Lira down during the testing
            logging.error('An error occurred, stopping test and saving metrics now')
        finally:
            self.save_metrics()

    def dump_metrics(self, path):
        with open(path, 'w') as file:
            json.dump(self.metrics, file)

    def dumps_metrics(self):
        return json.dumps(self.metrics)


def locust_agent_factory(payload, params, notification_ratio=1):
    """Factory method to generate Locust testing agents."""
    if params:
        auth_token = {'auth': params}

        class LocustLoadTestAgent(TaskSet):
            @task(notification_ratio)
            def send_notifications(self):
                self.client.post("/notifications", json=payload, params=auth_token)
    else:
        class LocustLoadTestAgent(TaskSet):
            @task(notification_ratio)
            def send_notifications(self):
                self.client.post("/notifications", json=payload)

    return LocustLoadTestAgent
