import docker


def get_client() -> docker.DockerClient:
    """Returns a docker.DockerClient instance."""
    return docker.from_env()
