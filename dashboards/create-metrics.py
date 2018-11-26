import argparse
import json
import logging
from google.cloud import logging as gcloud_logging


def main(service_account_path, pre_defined_metrics_json='metrics_template.json', google_project=None):
    logging.basicConfig(level=logging.INFO)

    # Instantiate a client from the service account JSON key path
    logging_client = gcloud_logging.Client.from_service_account_json(service_account_path)

    # Load pre-defined metrics JSON
    with open(pre_defined_metrics_json, 'r') as f:
        METRICS = json.load(f)

    # List the current metrics
    list_metrics(logging_client)

    # Create the necessary metrics from the pre-defined list
    if google_project:
        # Check if we are using the right service account JSON key
        assert logging_client.project == google_project
    google_project = logging_client.project

    for metric in METRICS:
        check_and_create_metrics(gcloud_log_client=logging_client, metric_json=metric, google_project=google_project)

    # List the current metrics again
    list_metrics(logging_client)

    # Double check
    assert len(METRICS) == len(list(logging_client.list_metrics()))


def list_metrics(gcloud_log_client):
    """List all of the log-based metrics that is currently available on the cloud.

    Args:
        gcloud_log_client (google.cloud.logging.client.Client): A concrete google cloud logging client instance.
    """
    logging.info("Listing all of the current metrics:")
    for metric in gcloud_log_client.list_metrics():
        print(metric.name)


def check_and_create_metrics(gcloud_log_client, metric_json, google_project):
    """Check the existence of a log-based metric, if it's not existing yet, create the metric.

    Args:
        gcloud_log_client (google.cloud.logging.client.Client): A concrete google cloud logging client instance.
        metric_json (dict): A dict representing a parameterized log-based metric. e.g.
            {
                "NAME": "Falcon-igniter-effective-release",
                "FILTER": " resource.type="container" logName="projects/{google_project}/logs/falcon" "
            }
        google_project (str): A string representing the google cloud project name.
    """
    logging.info("Loading the metric {}".format(metric_json))

    # The following line would not fail even if the metric_json is not parameterized :)
    metric = gcloud_log_client.metric(name=metric_json["NAME"],
                                      filter_=metric_json["FILTER"].format(google_project=google_project))

    if metric.exists():
        logging.warning("The current metric {} exists, skipping creating the metric.".format(metric.name))
    else:
        logging.info("Creating the metric {}.".format(metric.name))
        metric.create()
        logging.info("Created the metric {}.".format(metric.name))


def delete_metric(gcloud_log_client, metric_name):
    """Delete a metric based on the name of the metric.

    Args:
        gcloud_log_client (google.cloud.logging.client.Client): A concrete google cloud logging client instance.
        metric_name (str): The name of the target metric to be deleted.

    Raises:
        ValueError: If the metric does not exist.
    """
    logging.info("Loading the metric {}.".format(metric_name))
    existing_metric = gcloud_log_client.metric(metric_name)

    try:
        existing_metric.reload()
    except Exception:  # catch broad exceptions raised from google-grpc wrapper
        raise ValueError("The metric {} does not exist!".format(metric_name))

    logging.info("Deleting the metric {}.".format(existing_metric.name))
    existing_metric.delete()
    logging.info("Metric {} has been deleted.".format(existing_metric.name))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--service_account_path',
                        help='Path to the service account JSON key.')
    parser.add_argument('--pre_defined_metrics_json',
                        default='metrics_template.json',
                        help='Path to the pre-defined log-based metrics JSON file.')
    parser.add_argument('--google_project',
                        default=None,
                        help='A string representing the google cloud project name.')
    args = parser.parse_args()

    main(service_account_path=args.service_account_path,
         pre_defined_metrics_json=args.pre_defined_metrics_json,
         google_project=args.google_project)
