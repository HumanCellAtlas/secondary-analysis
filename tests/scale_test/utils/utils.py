import click
import hvac
import hvac.exceptions
import json
import requests
import uuid
from requests_http_signature import HTTPSignatureAuth
import pathlib


SUBSCRIPTION_QUERIES = {
    'AdapterSmartSeq2SingleCell': './subscription_queries/smartseq2-query.json',
    'AdapterOptimus': './subscription_queries/tenx_query.json'
}

def compose_label(label_string):
    """Compose a valid label for Lira from a string of object.

    Args:
        label_string (str): A valid string of dictionary.

    Returns:
        dict: A valid dict that describes a Cromwell workflow label.

    """
    try:
        return json.loads(label_string)
    except (json.decoder.JSONDecodeError, TypeError):
        return None


def send_notification(lira_url, auth_dict, notification):
    """Send a notification to a given Lira.

    Args:
        lira_url (str): A typical Lira url, e.g. https://pipelines.dev.data.humancellatlas.org/
        auth_dict (dict): Dictionary contains credentials for authenticating with Lira.
            It should have 'method' and 'value' as keys.
        notification (dict): A dict of notification content.

    Returns:
        requests.Response: The response object returned by Lira.
    """
    if auth_dict['method'] == 'token':
        response = requests.post(
            url=harmonize_url(lira_url) + 'notifications',
            json=notification,
            params={'auth': auth_dict['value']['auth_token']},
        )
    else:
        auth = HTTPSignatureAuth(
            key_id=auth_dict['value']['hmac_key_id'],
            key=auth_dict['value']['hmac_key_value'].encode('utf-8'),
        )
        response = requests.post(
            url=harmonize_url(lira_url) + 'notifications', json=notification, auth=auth
        )
    return response


def load_es_query(es_query_path):
    """Load the ElasticSearch query json file.

    Args:
        es_query_path (str): The path to the ES query json file which is used for making subscription in BlueBox.

    Returns:
        query_obj (dict): A dict of loaded es query content.
    """
    with open(es_query_path, 'r') as query_file:
        query_obj = json.load(query_file)
    return query_obj


def prepare_notification(
    bundle_uuid,
    bundle_version,
    subscription_id,
    workflow_name,
    es_query_path=None,
    label=None,
    transaction_id=None,
):
    """Compose the notification content from given values.

    Args:
        bundle_uuid (str): A Blue Box bundle uuid.
        bundle_version (str): A Blue Box bundle version.
        subscription_id (str): A valid Lira subscription id in Blue Box.
        workflow_name (str): The name of the workflow to start.
        es_query_path (str): The path to the ES query json file which is used for making subscription in BlueBox.
        label (str): A label to be added to the notification, which will then be added to the workflow started by Lira.
        transaction_id (str): A valid transaction id.

    Returns:
        notification (dict): A dict of valid notification content.

    """
    if not es_query_path:
        es_query_path = SUBSCRIPTION_QUERIES[workflow_name]
    notification = {
        'match': {'bundle_uuid': bundle_uuid, 'bundle_version': bundle_version},
        'subscription_id': subscription_id,
        'transaction_id': transaction_id or _prepare_transaction_id(),
        'es_query': load_es_query(es_query_path),
    }
    if label:
        notification['labels'] = label
    return notification


def subscription_probe(lira_url, workflow_name='AdapterSmartSeq2SingleCell'):
    """A probe to fetch the subscription id.

    This function performs as a probe, fetches the subscription id by hitting the /version endpoint of Lira.

    Args:
        lira_url (str): A typical Lira url, e.g. https://pipelines.dev.data.humancellatlas.org/
        workflow_name (str): The workflow to be invoked by the script.

    Returns:
        subscription_id (str): A valid subscription id.
    """
    response = requests.get(harmonize_url(lira_url) + 'version')
    response.raise_for_status()
    subscription_id = response.json()['workflow_info'][workflow_name]['subscription_id']
    return subscription_id


def dump_metrics(path, **kwargs):
    """Dump metrics to a JSON file.

    This function dumps all of the given keyword metrics arguments to a JSON file.
    Args:
        path (str): The path to a file.
        **kwargs: Arbitrary keyword metrics arguments.
    """
    metrics = {name: value for name, value in kwargs.items()}
    with open(path, 'w') as metrics_file:
        json.dump(metrics, metrics_file)


def _prepare_transaction_id():
    """Transaction UUID generator.

    This function generates a fake valid UUID.

    Returns:
        str: A fake transaction UUID generated by standard uuid lib.
    """
    return str(uuid.uuid4())


def harmonize_url(url):
    """Harmonize the url string.

    This function checks if url ends with slash, if not, add a slash to the url string.
    Args:
        url (str): A string of url.

    Returns:
        str: A string of url ends with slash.
    """
    url = url.rstrip('/')
    return url + '/'


def read_bundles(bundle_list_file):
    """Read bundles in to a dict from a file.

    This function expects the JSON file follows a pre-defined schema:
        [
            {"bundle_uuid": XXX, "bundle_version": XXX},
            {"bundle_uuid": XXX, "bundle_version": XXX}
        ]

    Args:
        bundle_list_file (str): A path to the JSON file.

    Returns:
        bundles (dict): A dict of bundles listed in the file.
    """
    with open(bundle_list_file) as f:
        bundles = json.load(f)
    return bundles


def required_checker(ctx, **kwargs):
    """Check if all keyword arguments are provided by the user.

    This function checks if all of the given keyword arguments are given by the user, if not, stop all of the current
        commandline session. This custom checker function is better than the required=True flag of Click for this use
        case since it also shows the full help text of the click commands.

    Args:
        ctx (click.Context): The special internal object that holds state relevant for the script execution at
            every single level. This is automatically passed in by Click.
        **kwargs: Arbitrary keyword command arguments.
    """
    for name, val in kwargs.items():
        if not val:
            click.echo('Error: Missing option "--{}".'.format(name))
            click.echo(ctx.get_help())
            ctx.exit()


def auth_checker(ctx):
    """A probe to check the auth_token.

    TODO: Add the auth probe back once Lira has a new auth endpoint.
    - (The auth check probe has been deprecated for now) This function performs as a probe, which validates the
    auth_token by sending a fake request to the Lira.
    - This function will ask the user for the authentication information to talk to Lira.

    Args:
        ctx (click.Context): The special internal object that holds state relevant for the script execution at
            every single level. This is automatically passed in by Click.

    Returns:
        valid_auth_dict (dict): Dictionary containing the valid information for authenticating with Lira.
    """
    auth_method = None
    lira_auth_dict = {'method': auth_method, 'value': {}}

    while auth_method not in ('token', 'hmac'):
        auth_method = click.prompt(
            'Please enter a valid auth method for Lira (token/hmac)',
            type=str,
            hide_input=False,
            default="hmac",
        )

    if auth_method == 'token':
        auth_token = click.prompt(
            'Please enter a valid auth_token for Lira (inputs are hidden)',
            type=str,
            hide_input=True,
        )
        lira_auth_dict['method'] = auth_method
        lira_auth_dict['value']['auth_token'] = auth_token

        valid_auth_dict = prepare_auth(lira_auth_dict)
    else:
        lira_auth_dict['method'] = auth_method
        lira_auth_dict['vault_server_url'] = click.prompt(
            'Please enter your full Vault server URL',
            type=str,
            hide_input=False,
            default="https://clotho.broadinstitute.org:8200",
        )
        lira_auth_dict['path_to_vault_token'] = click.prompt(
            'Please enter the path to your Vault token file',
            type=click.Path(exists=True),
            hide_input=False,
            default=(pathlib.Path.home() / '.vault-token').absolute(),
        )
        lira_auth_dict['path_to_hmac_cred'] = click.prompt(
            'Please enter the path to HMAC credentials in your Vault',
            type=str,
            hide_input=False,
            default="secret/dsde/mint/prod/lira/hmac_keys",
        )

        valid_auth_dict = prepare_auth(lira_auth_dict)

    return valid_auth_dict


def _get_vault_client(vault_server_url, path_to_vault_token):
    """Instantiate a Vault client based on the given information about Vault server.

    Args:
        vault_server_url (str): URL to your Vault server.
        path_to_vault_token (str): Full path to your vault token file. (You might need to do vault login to refresh
        the token file before calling this function)

    Returns:
        client (hvac.Client): A valid and authenticated Vault client.
    """
    with open(path_to_vault_token, 'r') as token_file:
        token = token_file.read()
        client = hvac.Client(url=vault_server_url, token=token)

    if not client.is_authenticated():
        raise AuthException(
            'Failed to authenticate with Vault, please check your Vault server URL and Vault token!'
        )
    else:
        return client


def _load_hmac_creds(vault_client, path_to_hmac_cred):
    """Load HMAC credentials from Vault.

    Args:
        vault_client (hvac.Client): A valid and authenticated Vault client.
        path_to_hmac_cred (str): Full path to your HMAC credentials in the Vault server.

    Returns:
        Tuple[str]: A tuple of (hmac_key_id, hmac_key_value) strings.
    """
    # this is the "double check" to make sure the client is not not stale
    if not vault_client.is_authenticated():
        raise AuthException(
            'Failed to authenticate with Vault, please check your Vault server URL and Vault token!'
        )

    try:
        vault_response = vault_client.read(path_to_hmac_cred)
    except hvac.exceptions.Forbidden:
        raise AuthException(
            'Permission Denied, please check your permissions and the path to the secret!'
        )

    if not vault_response or not vault_response.get('data'):
        raise IncorrectSecretException(
            'Invalid secret fetched, please check the path to the secret!'
        )

    hmac_key_id, hmac_key_value = list(vault_response.get('data').items())[0]
    return hmac_key_id, hmac_key_value


def prepare_auth(lira_auth_dict):
    """Prepare the the Auth dictionary for sending notifications.

    Args:
        lira_auth_dict (dict): Dictionary containing user inputs of the authentication information. It must have the key
            'method', and optionally, it could have the following keys: 'vault_server_url', 'path_to_vault_token',
            'path_to_hmac_cred'.

    Returns:
        valid_auth_dict (dict): Dictionary containing the valid information for authenticating with Lira.
    """
    auth_method = lira_auth_dict['method']
    valid_auth_dict = lira_auth_dict

    if auth_method == 'token':
        pass  # TODO: take advantage of Lira's /auth endpoint to check the auth information

    elif auth_method == 'hmac':
        vault_client = _get_vault_client(
            vault_server_url=valid_auth_dict.pop('vault_server_url'),
            path_to_vault_token=valid_auth_dict.pop('path_to_vault_token'),
        )
        hmac_key_id, hmac_key_value = _load_hmac_creds(
            vault_client=vault_client,
            path_to_hmac_cred=valid_auth_dict.pop('path_to_hmac_cred'),
        )
        valid_auth_dict['value']['hmac_key_id'] = hmac_key_id
        valid_auth_dict['value']['hmac_key_value'] = hmac_key_value
    else:
        raise AuthException(
            'Unknown auth method {0}, Lira only supports hmac/token methods'.format(
                auth_method
            )
        )
    return valid_auth_dict


class AuthException(Exception):
    pass


class IncorrectSecretException(Exception):
    pass
