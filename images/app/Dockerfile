FROM alpine:3.14.0

RUN apk --no-cache add \
    bash \
    netcat-openbsd \
    dhclient \
    curl \
    wget \
    vim \
    ethtool \
    tcpdump \
    conntrack-tools \
    bind-tools \
    busybox-extras \
    qemu-system-x86_64

RUN wget https://github.com/cirros-dev/cirros/releases/download/0.5.2/cirros-0.5.2-x86_64-uec.tar.gz -O /cirros-uec.tar.gz && \
    tar -xvf cirros-uec.tar.gz

COPY vm.sh /vm.sh
CMD bash -x vm.sh