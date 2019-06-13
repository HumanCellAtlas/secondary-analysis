import hvac
import os
import pathlib
from meteoroid import exceptions
import logging


VAULT_ADDR = "https://clotho.broadinstitute.org:8200"
VAULT_TOKEN = os.environ['VAULT_TOKEN']


def get_authenticated_vault_client(token: str) -> hvac.Client:
    """Returns an authenticated hvac.Client instance."""
    if pathlib.Path(token).is_file():
        logging.info("Reading the Vault token from file")
        with open(token, 'r') as token_file:
            token = token_file.read()

    client = hvac.Client(url=VAULT_ADDR, token=token)

    if not client.is_authenticated():
        raise exceptions.VaultAuthException(
            f"Failed to authenticate with Vault server {VAULT_ADDR}"
        )
    return client


def read_secret(client: hvac.Client, path: str, pure_data: bool = True) -> dict:
    """Returns the secret in a dictionary given the path in Vault."""
    secret = client.read(path=path)

    if not secret:
        raise exceptions.InvalidVaultSecretPath(
            f"Failed to retrieve secret from {path}"
        )

    if pure_data:
        secret = secret['data']
    return secret


def list_secrets(client: hvac.Client, path: str, pure_data: bool = True) -> dict:
    """Returns the secret list in a dictionary under the path given the path in Vault."""
    secret_list = client.list(path=path)

    if pure_data:
        secret_list = secret_list['data']
    return secret_list
