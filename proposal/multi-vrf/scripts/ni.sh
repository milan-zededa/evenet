#!/usr/bin/env bash

set -x

# This script is run from the zedbox container.
# It is used to configure everything for a local/vpn network instance except for ACLs
# (VRF netdev, bridge, dnsmasq, http server)
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

vrf_name="vrf${ni_index}"
br_name="br${ni_index}"
vrf_table=$((400+ni_index))

ni_veth="veth${ni_index}.1"
ni_veth_hwaddr="AA:AA:AA:AA:0${ni_index}:01"
zedbox_veth="veth${ni_index}"
zedbox_veth_hwaddr="AA:AA:AA:AA:0${ni_index}:00"

# 1. VRF device
ip link add ${vrf_name} type vrf table ${vrf_table}
ip link set dev ${vrf_name} up

# 2. zedbox<->VRF veth
#    - https://stbuehler.de/blog/article/2020/02/29/using_vrf__virtual_routing_and_forwarding__on_linux.html
#    - static ARP are needed here, broadcast does not work well if both veth ends are in the same namespace
ip link add name ${ni_veth} type veth peer name ${zedbox_veth}
ip link set dev ${ni_veth} master ${vrf_name}
ip link set dev ${ni_veth} address ${ni_veth_hwaddr}
ip link set dev ${zedbox_veth} address ${zedbox_veth_hwaddr}
ip link set ${ni_veth} up
ip addr add ${ni_veth_ipnet} dev ${ni_veth}
ip link set ${zedbox_veth} up
ip addr add ${zedbox_veth_ipnet} dev ${zedbox_veth}
arp -i ${zedbox_veth} -s ${ni_veth_ip} ${ni_veth_hwaddr}
arp -i ${ni_veth} -s ${zedbox_veth_ip} ${zedbox_veth_hwaddr}
# In the VPN network, XFRM device will encrypt a packet and send it through a VETH in the egress direction.
# However, strongSwan listens on the uplink-side of the VETH and the IP address of that side will be therefore
# used as a source IP. Once the packet crosses the VETH and gets routed for the second time (zone 999) it will
# be therefore perceived as a locally originating packet and yet being forwarded instead. We have to explicitly
# allow this case, otherwise the packet will get dropped.
echo 1 >/proc/sys/net/ipv4/conf/${zedbox_veth}/accept_local
echo 1 >/proc/sys/net/ipv4/conf/${ni_veth}/accept_local

# 3. bridge
ip link add name ${br_name} type bridge
ip link set dev ${br_name} master ${vrf_name}
ip link set dev ${br_name} up
ip addr add ${bridge_ipnet} dev ${br_name}

# 4. track connection for this NI separately
#    - https://lwn.net/Articles/370152/
iptables -t raw -A PREROUTING -i ${ni_veth} -j CT --zone ${ni_index}
iptables -t raw -A OUTPUT -o ${ni_veth} -j CT --zone ${ni_index}
iptables -t raw -A PREROUTING -i ${br_name} -j CT --zone ${ni_index}
iptables -t raw -A OUTPUT -o ${br_name} -j CT --zone ${ni_index}

iptables -t raw -A PREROUTING -i ${zedbox_veth} -j CT --zone 999
iptables -t raw -A OUTPUT -o ${zedbox_veth} -j CT --zone 999
iptables -t raw -A PREROUTING -i ${uplink} -j CT --zone 999
iptables -t raw -A OUTPUT -o ${uplink} -j CT --zone 999

# 5. configure MASQUERADE on both the ni-veth and the uplink interface
iptables -t nat -A POSTROUTING -o ${ni_veth} -s ${ni_subnet} -j MASQUERADE
iptables -t nat -A POSTROUTING -o ${uplink} -s ${ni_veth_ip},${zedbox_veth_ip} -j MASQUERADE

# 6. also SNAT ingress traffic with colliding source IP
iptables -t nat -A POSTROUTING -o ${zedbox_veth} -s ${ni_subnet} -j SNAT --to ${zedbox_veth_ip}

# 7. dnsmasq (also added here github.com ipset which is referenced in acl.sh)
cat <<EOF > /etc/dnsmasq-${br_name}.conf
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
dhcp-leasefile=/run/dnsmasq-${br_name}.leases
interface=${br_name}
dhcp-range=${dhcp_range}
ipset=/github.com/ipv4.github.com,ipv6.github.com
hostsdir=/run/hosts-${br_name}/
EOF
ipset -N ipv4.github.com hash:ip family inet
ipset -N ipv6.github.com hash:ip family inet6
mkdir -p /run/hosts-${br_name}/

# Run inside VRF using "ip vrf exec" (eBPF is being used behind the scenes).
# Alternatively, this can be achieved using LD_PRELOAD:
#   /usr/bin/setnif.sh ${vrf_name} dnsmasq -d -b -C /etc/dnsmasq-${br_name}.conf
cat <<EOF > /etc/supervisor.d/dnsmasq-${br_name}.conf
[program:dnsmasq-${br_name}]
command=ip vrf exec ${vrf_name} dnsmasq -d -b -C /etc/dnsmasq-${br_name}.conf
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

# 8. http server
cat <<EOF > /etc/supervisor.d/http-${br_name}.conf
[program:http-${br_name}]
command=bash -x /scripts/http.sh ni${ni_index}-cloud-init 80 ${bridge_ip} ${vrf_name}
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

iptables -A PREROUTING -t nat -i ${br_name} -d 169.254.169.254 -p tcp --dport 80 -j DNAT --to-destination ${bridge_ip}:80

supervisorctl reread
supervisorctl update