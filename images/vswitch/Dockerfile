FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    supervisor \
    dnsutils \
    iptables \
    ipset \
    vim \
    syslog-ng \
    netcat-openbsd \
    binutils \
    curl \
    wget \
    ethtool \
    tcpdump \
    iproute2 \
    net-tools \
    conntrack \
    iputils-ping && \
    rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/milan-zededa/dnsmasq.git \
  && cd dnsmasq \
  && make install \
  && cd .. \
  && rm -rf dnsmasq

RUN mkdir /etc/supervisor.d
COPY supervisor.conf /etc/supervisor.conf

# https://gist.github.com/markusfisch/51b1ce6c3ca9ce67e081
RUN wget https://gist.githubusercontent.com/markusfisch/51b1ce6c3ca9ce67e081/raw/57c51da2c33090e13e2800ce1d30eec91720d7af/setnif.sh -O /usr/bin/setnif.sh
RUN chmod u+x /usr/bin/setnif.sh

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor.conf"]