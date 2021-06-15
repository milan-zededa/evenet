#!/usr/bin/env bash

set -x

# This script is run from the zedbox container.
# It is used to configure everything for a local network instance except for ACLs
# (VRF netdev, bridge, dnsmasq, http server)
#
# Usage: local_ni.sh <ni-index> <ni-subnet> <bridge-ipnet> <dhcp-range> <uplink-interface>

function cut_mask() {
  echo ${1} | cut -d'/' -f1
}

ni_index=${1}
ni_subnet=${2}
bridge_ipnet=${3}
bridge_ip=$(cut_mask ${bridge_ipnet})
dhcp_range=${4}
uplink=${5}


vrf_name="vrf${ni_index}"
br_name="br${ni_index}"
ni_table=$((500+ni_index))

# 1. VRF device
ip link add ${vrf_name} type vrf table ${ni_table}
ip link set dev ${vrf_name} up

# 2. bridge
ip link add name ${br_name} type bridge
ip link set dev ${br_name} master ${vrf_name}
ip link set dev ${br_name} up
ip addr add ${bridge_ipnet} dev ${br_name}

# 3. track connection for this NI separately
#    - https://lwn.net/Articles/370152/
#    - TODO: seems with zone=0 iptables do not work well with VRFs
#              tcp      6 298 ESTABLISHED src=10.10.1.103 dst=169.254.169.254 sport=53682 dport=80 src=10.10.1.1 dst=10.10.1.103 sport=80 dport=53682 [ASSURED] mark=0 use=1
#                vs.
#              tcp      6 110 TIME_WAIT src=10.10.1.124 dst=169.254.169.254 sport=46142 dport=80 src=10.10.1.1 dst=10.10.1.124 sport=80 dport=46142 [ASSURED] mark=0 zone=1 use=1
iptables -t raw -A PREROUTING -i ${br_name} -j CT --zone 1 #${ni_index}
iptables -t raw -A OUTPUT -o ${br_name} -j CT --zone 1 #${ni_index}
iptables -t raw -A PREROUTING -i ${uplink} -j CT --zone 1

# 4. configure MASQUERADE on the uplink interface
iptables -t nat -A POSTROUTING -o ${uplink} -s ${ni_subnet} -j MASQUERADE

# 5. dnsmasq (also added here github.com ipset which is referenced in acl.sh)
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

cat <<EOF > /etc/supervisor.d/dnsmasq-${br_name}.conf
[program:dnsmasq-${br_name}]
command=/usr/bin/setnif.sh ${vrf_name} dnsmasq -d -b -C /etc/dnsmasq-${br_name}.conf
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

# 6. http server
cat <<EOF > /etc/supervisor.d/http-${br_name}.conf
[program:http-${br_name}]
command=/scripts/http.sh ni${ni_index}-cloud-init 80 ${bridge_ip} ${vrf_name}
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

iptables -A PREROUTING -t nat -i ${br_name} -d 169.254.169.254 -p tcp --dport 80 -j DNAT --to-destination ${bridge_ip}:80

supervisorctl reread
supervisorctl update