"""This is the unittest comes with the utils.py,
Run `pytest -vv` in the directory after you make any changes to utils.py.

TODO: Add more test cases, cover testing the CLI itself.
"""
import requests
import requests_mock
import pytest
import os
import time
from . import utils
import tempfile


curr_path = os.path.abspath(os.path.dirname(__file__))


def test_compose_label_returns_expected_dict_for_valid_default_string():
    default_string = '{' + \
        str('"comment": "scaling-test-{}"'.format(time.strftime('%Y-%m-%d'))) + '}'
    assert utils.compose_label(default_string) == {
        "comment": "scaling-test-{}".format(time.strftime('%Y-%m-%d'))
    }


def test_compose_label_returns_none_for_invalid_string():
    assert utils.compose_label('random_string') is None


def test_compose_label_returns_none_for_non_string():
    assert utils.compose_label(None) is None


def test_load_es_query_returns_valid_dict():
    assert utils.load_es_query(curr_path + '/test_data/smartseq2-query.json')[
        'query']['bool']['must'][0]['match']['files.process_json.processes.content.library_construction_approach'] == 'Smart-seq2'


def test_prepare_notification_returns_valid_notification_body():
    bundle_uuid, bundle_version = 'uuid', 'version'
    subscription_id, transaction_id = 's_id', 't_id'
    label = {'test-label-key', 'test-label-value'}
    es_query_path = curr_path + '/test_data/smartseq2-query.json'

    expected = {
        'match': {
            'bundle_uuid': bundle_uuid,
            'bundle_version': bundle_version,
        },
        'subscription_id': subscription_id,
        'transaction_id': transaction_id,
        'es_query': utils.load_es_query(es_query_path),
        'labels': label,
    }
    assert expected == utils.prepare_notification(bundle_uuid,
                                                  bundle_version,
                                                  es_query_path,
                                                  subscription_id,
                                                  label,
                                                  transaction_id)


@pytest.fixture()
def requests_mocker():
    with requests_mock.Mocker() as m:
        yield m


def test_subscription_probe_gets_back_smartseq2_subscription_id(requests_mocker):
    lira_url = 'http://pipelines.dev.data.humancellatlas.org'

    def _request_callback(request, context):
        context.status_code = 200
        return {
            'workflow_info': {
                'AdapterSmartSeq2SingleCell': {
                    'subscription_id': 'ss2_id'
                },
                'Optimus': {
                    'subscription_id': 'optimus_id'
                }
            }
        }

    requests_mocker.get(lira_url + '/version', json=_request_callback)

    assert utils.subscription_probe(lira_url, 'AdapterSmartSeq2SingleCell') == 'ss2_id'


def test_subscription_probe_gets_back_optimus_subscription_id(requests_mocker):
    lira_url = 'http://pipelines.dev.data.humancellatlas.org'

    def _request_callback(request, context):
        context.status_code = 200
        return {
            'workflow_info': {
                'AdapterSmartSeq2SingleCell': {
                    'subscription_id': 'ss2_id'
                },
                'Optimus': {
                    'subscription_id': 'optimus_id'
                }
            }
        }

    requests_mocker.get(lira_url + '/version', json=_request_callback)

    assert utils.subscription_probe(lira_url, 'Optimus') == 'optimus_id'


def test_dump_metrics_dumps_files():
    temp_dir = tempfile.mkdtemp()

    temp_metrics_file = os.path.join(temp_dir, 'metrics.json')

    utils.dump_metrics(temp_metrics_file, key='value')

    with open(temp_metrics_file) as f:
        assert f.read() == '{"key": "value"}'


def test_send_notification_returns_ok_with_valid_params(requests_mocker):
    params = {'auth': 'token'}
    lira_url = 'http://pipelines.dev.data.humancellatlas.org'

    def _valid_request_callback(request, context):
        context.status_code = 201
        return {'id': 'Submitted'}

    def _invalid_request_callback(request, context):
        context.status_code = 401
        return {'error': 'Unauthorized'}

    if params == {'auth': 'token'}:
        requests_mocker.post(lira_url + '/notifications', json=_valid_request_callback)
    else:
        requests_mocker.post(lira_url + '/notifications', json=_invalid_request_callback)

    assert 201 == utils.send_notification(lira_url, params.get(
        'auth'), {'notification': 'placeholder'}).status_code


def test_send_notification_returns_error_with_invalid_params(requests_mocker):
    params = {'auth': 'wrong-token'}
    lira_url = 'http://pipelines.dev.data.humancellatlas.org'

    def _valid_request_callback(request, context):
        context.status_code = 201
        return {'id': 'Submitted'}

    def _invalid_request_callback(request, context):
        context.status_code = 401
        return {'error': 'Unauthorized'}

    if params == {'auth': 'token'}:
        requests_mocker.post(lira_url + '/notifications', json=_valid_request_callback)
    else:
        requests_mocker.post(lira_url + '/notifications', json=_invalid_request_callback)

    assert 401 == utils.send_notification(lira_url, params.get(
        'auth'), {'notification': 'placeholder'}).status_code
