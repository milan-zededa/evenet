#!/usr/bin/env bash

set -x

# This script is run from the zedbox container.
# It is used to configure ACLs for all NIs using iptables.
#
# Usage: acls.sh <veth-net-prefix>
veth_net_prefix=${1}

# Black hole for rejected flows = dummy interface + PBR.
function configure_blackhole() {
  ns=${1}
  dummy="flow-mon-dummy"
  ip netns exec ${ns} ip link add name ${dummy} type dummy
  ip netns exec ${ns} ip link set dev ${dummy} up
  ip netns exec ${ns} ip link set dev ${dummy} arp off
  ip netns exec ${ns} ip rule add priority 1000 fwmark 0xffffff/0xffffff lookup 500
  ip netns exec ${ns} ip route add table 500 default dev ${dummy}
}

# Chain created to mark and accept flows matched by an ACCEPT ACE.
function configure_mark_and_accept_chain() {
  ns=${1}
  chain=${2}
  mark=${3}
  ip netns exec ${ns} iptables -N ${chain} -t mangle
  ip netns exec ${ns} iptables -A ${chain} -t mangle -j CONNMARK --restore-mark
  ip netns exec ${ns} iptables -A ${chain} -t mangle -m mark ! --mark 0x0 -j ACCEPT
  ip netns exec ${ns} iptables -A ${chain} -t mangle -j CONNMARK --set-mark ${mark}
  ip netns exec ${ns} iptables -A ${chain} -t mangle -j CONNMARK --restore-mark
  ip netns exec ${ns} iptables -A ${chain} -t mangle -j ACCEPT
}

function get_app_ip() {
  app=${1}
  interface=${2}
  ip netns exec ${app} ip -f inet addr show ${interface} | sed -En -e 's/.*inet ([0-9.]+).*/\1/p'
}

function local_ipset() {
  ni=${1}
  ip netns exec ${ni} ipset -N ipv4.local hash:net family inet
  ip netns exec ${ni} ipset -A ipv4.local 224.0.0.0/4
  ip netns exec ${ni} ipset -A ipv4.local 255.255.255.255
  ip netns exec ${ni} ipset -A ipv4.local 0.0.0.0
}

# Mark traffic originating from local processes
function mark_output_traffic() {
  ns=${1}
  ip netns exec ${ns} iptables -A OUTPUT -t mangle -j CONNMARK --restore-mark
  ip netns exec ${ns} iptables -A OUTPUT -t mangle -m mark ! --mark 0x0 -j ACCEPT
  ip netns exec ${ns} iptables -A OUTPUT -t mangle -j CONNMARK --set-mark 0x5
  ip netns exec ${ns} iptables -A OUTPUT -t mangle -j CONNMARK --save-mark
}

# Mark traffic not marked by any installed mangle rule.
function mark_remaining_traffic() {
  ns=${1}
  ip netns exec ${ns} iptables -A PREROUTING -t mangle -j CONNMARK --restore-mark
  ip netns exec ${ns} iptables -A PREROUTING -t mangle -m mark ! --mark 0x0 -j ACCEPT
  ip netns exec ${ns} iptables -A PREROUTING -t mangle -j CONNMARK --set-mark 0xffffff
  ip netns exec ${ns} iptables -A PREROUTING -t mangle -j CONNMARK --save-mark
}

for ns in ni1 ni2 ni3; do
  configure_blackhole ${ns}
  mark_output_traffic ${ns}
  local_ipset ${ns}
done


# App1 ACLs
# ---------
# - NI1: allow DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain ni1 proto-nbu1x1-6 0x6
ip netns exec ni1 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x1+ -d 10.10.1.1 -p udp -m multiport --dports bootps,domain -j proto-nbu1x1-6
configure_mark_and_accept_chain ni1 proto-nbu1x1-7 0x7
ip netns exec ni1 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x1+ -d 10.10.1.1 -p tcp --dport domain -j proto-nbu1x1-7
configure_mark_and_accept_chain ni1 proto-nbu1x1-8 0x8
ip netns exec ni1 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x1+ -d 169.254.169.254 -p tcp --dport http -j proto-nbu1x1-8
# - NI1: allow *github.com
configure_mark_and_accept_chain ni1 nbu1x1-1 0x1000001
ip netns exec ni1 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x1+ -m set --match-set ipv4.github.com dst -j nbu1x1-1
# - NI1: allow <uplink-subnets> (how else to allow hairpinning to port-mapped app2?)
configure_mark_and_accept_chain ni1 nbu1x1-2 0x1000002
ip netns exec ni1 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x1+ -d 192.168.0.0/16 -j nbu1x1-2
# - NI1: drop the rest
configure_mark_and_accept_chain ni1 drop-all-nbu1x1 0x1ffffff
ip netns exec ni1 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x1+ -j drop-all-nbu1x1

# - NI2: allow DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain ni2 proto-nbu2x1-6 0x6
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu2x1+ -d 192.168.1.1 -p udp -m multiport --dports bootps,domain -j proto-nbu2x1-6
configure_mark_and_accept_chain ni2 proto-nbu2x1-7 0x7
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu2x1+ -d 192.168.1.1 -p tcp --dport domain -j proto-nbu2x1-7
configure_mark_and_accept_chain ni2 proto-nbu2x1-8 0x8
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu2x1+ -d 169.254.169.254 -p tcp --dport http -j proto-nbu2x1-8
# - NI2: allow eidset, fport=80
configure_mark_and_accept_chain ni2 nbu2x1-1 0x1000001
ip netns exec ni2 ipset -N ipv4.eids.nbu2x1 hash:ip family inet
ip netns exec ni2 ipset -A ipv4.eids.nbu2x1 $(get_app_ip app2 nbu1x2.1)
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu2x1+ -m set --match-set ipv4.eids.nbu2x1 dst -p tcp --dport 80 -j nbu2x1-1
# - NI2: drop the rest
configure_mark_and_accept_chain ni2 drop-all-nbu2x1 0x1ffffff
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu2x1+ -j drop-all-nbu2x1


# App2 ACLs
# ---------
# - NI2: allow DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain ni2 proto-nbu1x2-6 0x6
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x2+ -d 192.168.1.1 -p udp -m multiport --dports bootps,domain -j proto-nbu1x2-6
configure_mark_and_accept_chain ni2 proto-nbu1x2-7 0x7
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x2+ -d 192.168.1.1 -p tcp --dport domain -j proto-nbu1x2-7
configure_mark_and_accept_chain ni2 proto-nbu1x2-8 0x8
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x2+ -d 169.254.169.254 -p tcp --dport http -j proto-nbu1x2-8
# - NI2: allow eidset, fport=80
configure_mark_and_accept_chain ni2 nbu1x2-1 0x2000001
ip netns exec ni2 ipset -N ipv4.eids.nbu1x2 hash:ip family inet
ip netns exec ni2 ipset -A ipv4.eids.nbu1x2 $(get_app_ip app1 nbu2x1.1)
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x2+ -m set --match-set ipv4.eids.nbu1x2 dst -p tcp --dport 80 -j nbu1x2-1
# - NI2: allow portmap 8080:80
configure_mark_and_accept_chain ni2 nbu1x2-2 0x2000002
#    - egress
#    - TODO: is this needed? Connection is initiated from outside (ot another app) and at this point it should be already marked.
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x2+ -p tcp --sport 80 -j nbu1x2-2
#    - ingress coming from NI2
#    - TODO: should every app automatically get access to all portmaps in the same network?
#            Currently this is inconsistent. Apps whose drop-all rule precede this will not get implicit access to port maps.
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -d 192.168.0.2 -p tcp --dport 8080 -j nbu1x2-2
#    - ingress coming from zedbox
ip netns exec ni2 iptables -A PREROUTING -t mangle -i veth2.1 -d ${veth_net_prefix}.6 -p tcp --dport 8080 -j nbu1x2-2
# - NI2: drop the rest
configure_mark_and_accept_chain ni2 drop-all-nbu1x2 0x2ffffff
ip netns exec ni2 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x2+ -j drop-all-nbu1x2

# - NI2: portmap 8080:80
#    - coming to zedbox NS from outside:
iptables -A PREROUTING -t nat -i eth0 -d 192.168.0.2 -p tcp --dport 8080 -j DNAT --to-destination ${veth_net_prefix}.6:8080
#    - coming to zedbox NS from NI1 (hairpin allowed here because NI1 and NI2 networks use the same uplink):
iptables -A PREROUTING -t nat -i veth1 -d 192.168.0.2 -p tcp --dport 8080 -j DNAT --to-destination ${veth_net_prefix}.6:8080
#    - coming to NI2 through bridge:
ip netns exec ni2 iptables -A PREROUTING -t nat -i br -d 192.168.0.2 -p tcp --dport 8080 -j DNAT --to-destination $(get_app_ip app2 nbu1x2.1):80
#    - coming to NI2 through veth:
ip netns exec ni2 iptables -A PREROUTING -t nat -i veth2.1 -d ${veth_net_prefix}.6 -p tcp --dport 8080 -j DNAT --to-destination $(get_app_ip app2 nbu1x2.1):80

# App3 ACLs
# ---------
# - NI3: allow DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain ni3 proto-nbu1x3-6 0x6
ip netns exec ni3 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x3+ -d 10.10.1.1 -p udp -m multiport --dports bootps,domain -j proto-nbu1x3-6
configure_mark_and_accept_chain ni3 proto-nbu1x3-7 0x7
ip netns exec ni3 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x3+ -d 10.10.1.1 -p tcp --dport domain -j proto-nbu1x3-7
configure_mark_and_accept_chain ni3 proto-nbu1x3-8 0x8
ip netns exec ni3 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x3+ -d 169.254.169.254 -p tcp --dport http -j proto-nbu1x3-8
# - NI3: allow all (0.0.0.0/0)
configure_mark_and_accept_chain ni3 nbu1x3-1 0x3000001
ip netns exec ni3 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x3+ -d 0.0.0.0/0 -j nbu1x3-1
# - NI3: drop the rest
configure_mark_and_accept_chain ni3 drop-all-nbu1x3 0x3ffffff
ip netns exec ni3 iptables -A PREROUTING -t mangle -i br -m physdev --physdev-in nbu1x3+ -j drop-all-nbu1x3


# App4 ACLs
# ---------
# - (switch) N4 - ingress direction: allow ingress DNS, BOOTP, cloud-init HTTP
ip netns exec ni4 iptables -A FORWARD -t filter -o eth2 -m physdev --physdev-out nbu1x4+ -p udp -m multiport --sports bootps,domain -j ACCEPT
ip netns exec ni4 iptables -A FORWARD -t filter -o eth2 -m physdev --physdev-out nbu1x4+ -p tcp --sport domain -j ACCEPT
# - (switch) N4 - ingress direction: allow 192.168.0.0/16 but limit to 5/s, bursts of 15
#     - TODO: this one is weird, why not to use --physdev-out?
ip netns exec ni4 iptables -A FORWARD -t filter -i eth2 -o eth2 -s 192.168.0.0/16 -m limit --limit 5/sec --limit-burst 15 -j ACCEPT
# - (switch) N4 - ingress direction: block the rest
ip netns exec ni4 iptables -A FORWARD -t filter -o eth2 -m physdev --physdev-out nbu1x4+ -j DROP

# - (switch) N4 - egress direction: allow ingress DNS, BOOTP, cloud-init HTTP
ip netns exec ni4 iptables -A PREROUTING -t raw -i eth2 -m physdev --physdev-in nbu1x4+ -p udp -m multiport --dports bootps,domain -j ACCEPT
ip netns exec ni4 iptables -A PREROUTING -t raw -i eth2 -m physdev --physdev-in nbu1x4+ -p tcp --dport domain -j ACCEPT
# - (switch) N4 - egress direction: allow 192.168.0.0/16 but limit to 5/s, bursts of 15
ip netns exec ni4 iptables -A PREROUTING -t raw -i eth2 -m physdev --physdev-in nbu1x4+ -d 192.168.0.0/16 -m limit --limit 5/sec --limit-burst 15 -j ACCEPT
# - (switch) N4 - egress direction: block the rest
ip netns exec ni4 iptables -A PREROUTING -t raw -i eth2 -m physdev --physdev-in nbu1x4+ -j DROP

# - (switch) N4 - mark DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain ni4 proto-eth2-nbu1x4-6 0x6
ip netns exec ni4 iptables -A PREROUTING -t mangle -i eth2 -m physdev --physdev-in nbu1x4+ -d 192.168.2.1 -p udp -m multiport --dports bootps,domain -j proto-eth2-nbu1x4-6
configure_mark_and_accept_chain ni4 proto-eth2-nbu1x4-7 0x7
ip netns exec ni4 iptables -A PREROUTING -t mangle -i eth2 -m physdev --physdev-in nbu1x4+ -d 192.168.2.1 -p tcp --dport domain -j proto-eth2-nbu1x4-7
configure_mark_and_accept_chain ni4 proto-eth2-nbu1x4-8 0x8
ip netns exec ni4 iptables -A PREROUTING -t mangle -i eth2 -m physdev --physdev-in nbu1x4+ -d 169.254.169.254 -p tcp --dport http -j proto-eth2-nbu1x4-8
# - (switch) N4 - mark dst=192.168.0.0/16 (ACE) in both directions
configure_mark_and_accept_chain ni4 eth2-nbu1x4-1 0x4000001
ip netns exec ni4 iptables -A PREROUTING -t mangle -i eth2 -m physdev --physdev-in nbu1x4+ -d 192.168.0.0/16 -j eth2-nbu1x4-1
# TODO: why not to use --physdev-out?
ip netns exec ni4 iptables -A PREROUTING -t mangle -i eth2 -s 192.168.0.0/16 -j eth2-nbu1x4-1
# Note: dropped flows are not marked for switch networks


# Remaining common rules.
for ns in ni1 ni2 ni3 ni4; do
  # Special mark for ICMP
  ip netns exec ${ns} iptables -A PREROUTING -t mangle -p icmp -j CONNMARK --set-mark 0x9
  # Mark (and drop) whatever is left unmarked.
  mark_remaining_traffic ${ns}
done