#!/usr/bin/env bash

set -x

# This script is run from the GW container.
# This script configures and starts dnsmasq to act as an external DNS/DHCP service for the switch network NI4.

cat <<EOF > /etc/dnsmasq.conf
except-interface=lo
bind-interfaces
quiet-dhcp
quiet-dhcp6
no-hosts
no-ping
bogus-priv
stop-dns-rebind
rebind-localhost-ok
neg-ttl=10
dhcp-ttl=600
log-queries
log-dhcp
dhcp-leasefile=/run/dnsmasq.leases
interface=gw2
dhcp-range=192.168.2.50,192.168.2.150,60m
EOF

cat <<EOF > /etc/supervisor.d/dnsmasq.conf
[program:dnsmasq]
command=dnsmasq -d -b -C /etc/dnsmasq.conf
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

supervisorctl reread
supervisorctl update