FROM alpine:3.14.0

RUN apk --no-cache add \
    build-base \
    bash \
    git \
    supervisor \
    bind-tools \
    iptables \
    ipset \
    vim \
    netcat-openbsd \
    binutils \
    curl \
    wget \
    ethtool \
    tcpdump \
    conntrack-tools \
    strongswan \
    dnsmasq

RUN mkdir /etc/supervisor.d
COPY supervisord.conf /etc/supervisord.conf

# https://gist.github.com/markusfisch/51b1ce6c3ca9ce67e081
COPY setnif.sh /usr/bin/setnif.sh

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
