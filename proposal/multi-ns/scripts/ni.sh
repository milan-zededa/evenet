#!/usr/bin/env bash

set -x

# This script is run from a network instance container.
# It is used to configure everything for a local/vpn network instance except for ACLs
# (zedbox<->ni veth, bridge, default route, dnsmasq, http server)
#
# Usage: ni.sh <ni-index> <ni-subnet> <bridge-ipnet> <dhcp-range> <zedbox-veth-ipnet> <ni-veth-ipnet> <uplink-interface>

function cut_mask() {
  echo ${1} | cut -d'/' -f1
}

ni_index=${1}
ni_subnet=${2}
bridge_ipnet=${3}
bridge_ip=$(cut_mask ${bridge_ipnet})
dhcp_range=${4}
zedbox_veth_ipnet=${5}
zedbox_veth_ip=$(cut_mask ${zedbox_veth_ipnet})
ni_veth_ipnet=${6}
ni_veth_ip=$(cut_mask ${ni_veth_ipnet})
uplink=${7}

ni_veth="veth${ni_index}.1"
zedbox_veth="veth${ni_index}"

# 1. zedbox<->ni veth
ip link add name ${ni_veth} type veth peer name ${zedbox_veth}
ip link set ${zedbox_veth} netns zedbox
ip link set ${ni_veth} up
ip addr add ${ni_veth_ipnet} dev ${ni_veth}
ip netns exec zedbox ip link set ${zedbox_veth} up
ip netns exec zedbox ip addr add ${zedbox_veth_ipnet} dev ${zedbox_veth}

# 2. bridge
ip link add name br type bridge
ip link set dev br up
ip addr add ${bridge_ipnet} dev br

# 3. default route
ip route add default via ${zedbox_veth_ip} dev ${ni_veth}

# 4. configure MASQUERADE on both the ni-veth and the uplink interface
iptables -t nat -A POSTROUTING -o ${ni_veth} -s ${ni_subnet} -j MASQUERADE
ip netns exec zedbox iptables -t nat -A POSTROUTING -o ${uplink} -s ${ni_veth_ip}/32 -j MASQUERADE

# 5. also SNAT ingress traffic with colliding source IP
ip netns exec zedbox iptables -t nat -A POSTROUTING -o ${zedbox_veth} -s ${ni_subnet} -j SNAT --to ${zedbox_veth_ip}

# 6. dnsmasq (also added here github.com ipset which is referenced in acl.sh)
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
interface=br
dhcp-range=${dhcp_range}
ipset=/github.com/ipv4.github.com,ipv6.github.com
hostsdir=/run/hosts/
EOF
ipset -N ipv4.github.com hash:ip family inet
ipset -N ipv6.github.com hash:ip family inet6
mkdir -p /run/hosts/

cat <<EOF > /etc/supervisor.d/dnsmasq.conf
[program:dnsmasq]
command=dnsmasq -d -b -C /etc/dnsmasq.conf
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

# 7. http server
cat <<EOF > /etc/supervisor.d/http.conf
[program:http]
command=bash -x /scripts/http.sh ni${ni_index}-cloud-init 80 ${bridge_ip}
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

iptables -A PREROUTING -t nat -i br -d 169.254.169.254 -p tcp --dport 80 -j DNAT --to-destination ${bridge_ip}:80

supervisorctl reread
supervisorctl update