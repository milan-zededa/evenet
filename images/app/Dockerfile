FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    netcat-openbsd \
    isc-dhcp-client \
    binutils \
    curl \
    wget \
    vim \
    ethtool \
    tcpdump \
    iproute2 \
    net-tools \
    conntrack \
    dnsutils \
    iputils-ping && \
    rm -rf /var/lib/apt/lists/*