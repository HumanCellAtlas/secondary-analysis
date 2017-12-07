FROM ubuntu:17.04

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get -y install software-properties-common && \
    apt-get -y install --no-install-recommends \
    python3.6 \
    python3-pip \
    python3-setuptools \
    python3-wheel && \
    add-apt-repository ppa:certbot/certbot && \
    apt-get update && \
    apt-get -y install --no-install-recommends \
    vim \
    git \
    curl \
    certbot

RUN mkdir /certs
WORKDIR /certs

RUN pip3 install awscli --upgrade && \
    git clone https://github.com/jed/certbot-route53.git && \
    chmod u+x certbot-route53/certbot-route53.sh
