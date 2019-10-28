This directory contains get_certs.sh, for getting a new TLS certificate.
The script builds the docker image in the root of this repo, then runs
a command inside it to renew a certificate using certbot.

Requirements
------------
The docker container uses aws cli commands, which require credentials
to be passed into the container via environment variables.

You must set the AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment
variables before running the script, to authenticate as a user with 
permissions to edit our DNS records.

For example:
```
export AWS_ACCESS_KEY_ID=foo
export AWS_SECRET_ACCESS_KEY=bar
```

Usage
-----
```
bash get_certs.sh work_dir domain
```
where work_dir is the directory you'd like certificate to be written to
and domain is the domain you'd like to obtain a certificate for

Example
-------
```
bash get_certs.sh $(pwd) pipelines.dev.data.humancellatlas.org
```
This will obtain a certificate for pipelins.dev.data.humancellatlas.org and
write it to the current working diretory in letsencrypt/live/pipelines.dev.data.humancellatlas.org/
