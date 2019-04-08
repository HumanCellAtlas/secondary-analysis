import json
import arrow
import mock
from . import failure_analysis


def test_cromwell_query_params():
    start = arrow.get('2018-05-14 12:00:00').replace(tzinfo='US/Eastern')
    end = arrow.get('2018-05-14 14:30:00').replace(tzinfo='US/Eastern')
    name = 'TestWorkflow'
    label = 'comment:scale-test'
    query = failure_analysis.Query.factory(
        start=arrow.get(start).replace(tzinfo='US/Eastern'),
        end=arrow.get(end).replace(tzinfo='US/Eastern'),
        name=name,
        statuses=['Failed', 'Aborted'],
        labels=['comment:scale-test'],
    )
    query_params = failure_analysis.cromwell_query_params(query)
    expected_query_params = [
        {'start': '2018-05-14T16:00:00.000000Z'},
        {'end': '2018-05-14T18:30:00.000000Z'},
        {'name': name},
        {'status': 'Failed'},
        {'status': 'Aborted'},
        {'label': label},
    ]
    for each in expected_query_params:
        assert each in query_params


def test_find_duplicate_bundles():
    bundle_ids = [
        'bundle_1',
        'bundle_1',
        'bundle_2',
        'bundle_2',
        'bundle_2',
        'bundle_3',
    ]
    duplicate_bundles = failure_analysis.find_duplicate_bundle_ids(bundle_ids)
    expected_duplicates = {'bundle_1': 2, 'bundle_2': 3}
    assert duplicate_bundles == expected_duplicates


def test_sort_workflows_by_status():
    with open('test_data/adapter_metrics.json') as f:
        workflows = json.load(f)
    summary = failure_analysis.sort_workflows_by_status(workflows)
    n_success = [
        workflow for workflow in workflows if workflow['status'] == 'Succeeded'
    ]
    n_failed = [workflow for workflow in workflows if workflow['status'] == 'Failed']
    n_aborted = [workflow for workflow in workflows if workflow['status'] == 'Aborted']
    assert len(summary['Succeeded']) == len(n_success)
    assert len(summary['Failed']) == len(n_failed)
    assert len(summary['Aborted']) == len(n_aborted)


@mock.patch('scale_test.analysis.failure_analysis.get_gcs_file')
def test_get_failure_message(mock_get_gcs_file):
    mock_get_gcs_file.return_value = failure_analysis.ERRORS['LOCK_EXCEPTION']
    with open('test_data/adapter_metrics.json') as f:
        workflows = json.load(f)
    failed_workflow = [w for w in workflows if w['status'] == 'Failed'][0]
    task = [t for t in failed_workflow['calls'] if t['status'] == 'Failed'][0]
    message = failure_analysis.get_failure_message(task, record_std_err=False)
    assert message == failure_analysis.ERRORS['LOCK_EXCEPTION']


def test_group_workflows_by_failed_task():
    with open('test_data/adapter_metrics.json') as f:
        workflows = json.load(f)
    failed_workflows = [w for w in workflows if w['status'] == 'Failed']
    grouped_workflows = failure_analysis.group_workflows_by_failed_task(
        failed_workflows
    )
    assert len(grouped_workflows['submit.stage_and_confirm']) == 3
