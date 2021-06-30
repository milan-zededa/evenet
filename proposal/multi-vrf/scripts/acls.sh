#!/usr/bin/env bash

set -x

# This script is run from the zedbox container.
# It is used to configure ACLs using iptables.
#
# Usage: acls.sh <veth-net-prefix>
veth_net_prefix=${1}

# Black hole for rejected flows = dummy interface + PBR.
function configure_blackhole() {
  vrf=${1}
  dummy="dummy-${vrf}"
  ip link add name ${dummy} type dummy
  ip link set dev ${dummy} master ${vrf}
  ip link set dev ${dummy} up
  ip link set dev ${dummy} arp off
  # priority=1000 is already used for VRFs
  ip rule add priority 100 fwmark 0xffffff/0xffffff lookup 100
  ip route add table 100 default dev ${dummy}
}

# Chain created to mark and accept flows matched by an ACCEPT ACE.
function configure_mark_and_accept_chain() {
  chain=${1}
  mark=${2}
  iptables -N ${chain} -t mangle
  iptables -A ${chain} -t mangle -j CONNMARK --restore-mark
  iptables -A ${chain} -t mangle -m mark ! --mark 0x0 -j ACCEPT
  iptables -A ${chain} -t mangle -j CONNMARK --set-mark ${mark}
  iptables -A ${chain} -t mangle -j CONNMARK --restore-mark
  iptables -A ${chain} -t mangle -j ACCEPT
}

function get_app_ip() {
  app=${1}
  interface=${2}
  ip netns exec ${app} ip -f inet addr show ${interface} | sed -En -e 's/.*inet ([0-9.]+).*/\1/p'
}

function local_ipset() {
  ipset -N ipv4.local hash:net family inet
  ipset -A ipv4.local 224.0.0.0/4
  ipset -A ipv4.local 255.255.255.255
  ipset -A ipv4.local 0.0.0.0
}

# Mark traffic originating from local processes
function mark_output_traffic() {
  iptables -A OUTPUT -t mangle -j CONNMARK --restore-mark
  iptables -A OUTPUT -t mangle -m mark ! --mark 0x0 -j ACCEPT
  iptables -A OUTPUT -t mangle -j CONNMARK --set-mark 0x5
  iptables -A OUTPUT -t mangle -j CONNMARK --save-mark
}

# Mark traffic not marked by any installed mangle rule.
function mark_remaining_traffic() {
  iptables -A PREROUTING -t mangle -j CONNMARK --restore-mark
  iptables -A PREROUTING -t mangle -m mark ! --mark 0x0 -j ACCEPT
  iptables -A PREROUTING -t mangle -j CONNMARK --set-mark 0xffffff
  iptables -A PREROUTING -t mangle -j CONNMARK --save-mark
}

for vrf in vrf1 vrf2 vrf3 vrf4 vrf5; do
  configure_blackhole ${vrf}
done

mark_output_traffic
local_ipset


# App1 ACLs
# ---------
# - NI1: allow DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain proto-nbu1x1-6 0x6
iptables -A PREROUTING -t mangle -i br1 -m physdev --physdev-in nbu1x1+ -d 10.10.1.1 -p udp -m multiport --dports bootps,domain -j proto-nbu1x1-6
configure_mark_and_accept_chain proto-nbu1x1-7 0x7
iptables -A PREROUTING -t mangle -i br1 -m physdev --physdev-in nbu1x1+ -d 10.10.1.1 -p tcp --dport domain -j proto-nbu1x1-7
configure_mark_and_accept_chain proto-nbu1x1-8 0x8
iptables -A PREROUTING -t mangle -i br1 -m physdev --physdev-in nbu1x1+ -d 169.254.169.254 -p tcp --dport http -j proto-nbu1x1-8
# - NI1: allow *github.com
configure_mark_and_accept_chain nbu1x1-1 0x1000001
iptables -A PREROUTING -t mangle -i br1 -m physdev --physdev-in nbu1x1+ -m set --match-set ipv4.github.com dst -j nbu1x1-1
# - NI1: allow <uplink-subnets> (how else to allow hairpinning to port-mapped app2?)
configure_mark_and_accept_chain nbu1x1-2 0x1000002
iptables -A PREROUTING -t mangle -i br1 -m physdev --physdev-in nbu1x1+ -d 192.168.0.0/16 -j nbu1x1-2
# - NI1: drop the rest
configure_mark_and_accept_chain drop-all-nbu1x1 0x1ffffff
iptables -A PREROUTING -t mangle -i br1 -m physdev --physdev-in nbu1x1+ -j drop-all-nbu1x1

# - NI2: allow DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain proto-nbu2x1-6 0x6
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu2x1+ -d 192.168.1.1 -p udp -m multiport --dports bootps,domain -j proto-nbu2x1-6
configure_mark_and_accept_chain proto-nbu2x1-7 0x7
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu2x1+ -d 192.168.1.1 -p tcp --dport domain -j proto-nbu2x1-7
configure_mark_and_accept_chain proto-nbu2x1-8 0x8
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu2x1+ -d 169.254.169.254 -p tcp --dport http -j proto-nbu2x1-8
# - NI2: allow eidset, fport=80
configure_mark_and_accept_chain nbu2x1-1 0x1000001
ipset -N ipv4.eids.nbu2x1 hash:ip family inet
ipset -A ipv4.eids.nbu2x1 $(get_app_ip app2 nbu1x2.1)
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu2x1+ -m set --match-set ipv4.eids.nbu2x1 dst -p tcp --dport 80 -j nbu2x1-1
# - NI2: drop the rest
configure_mark_and_accept_chain drop-all-nbu2x1 0x1ffffff
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu2x1+ -j drop-all-nbu2x1


# App2 ACLs
# ---------
# - NI2: allow DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain proto-nbu1x2-6 0x6
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu1x2+ -d 192.168.1.1 -p udp -m multiport --dports bootps,domain -j proto-nbu1x2-6
configure_mark_and_accept_chain proto-nbu1x2-7 0x7
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu1x2+ -d 192.168.1.1 -p tcp --dport domain -j proto-nbu1x2-7
configure_mark_and_accept_chain proto-nbu1x2-8 0x8
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu1x2+ -d 169.254.169.254 -p tcp --dport http -j proto-nbu1x2-8
# - NI2: allow eidset, fport=80
configure_mark_and_accept_chain nbu1x2-1 0x2000001
ipset -N ipv4.eids.nbu1x2 hash:ip family inet
ipset -A ipv4.eids.nbu1x2 $(get_app_ip app1 nbu2x1.1)
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu1x2+ -m set --match-set ipv4.eids.nbu1x2 dst -p tcp --dport 80 -j nbu1x2-1
# - NI2: allow portmap 8080:80
configure_mark_and_accept_chain nbu1x2-2 0x2000002
#    - egress
#    - TODO: is this needed? Connection is initiated from outside (ot another app) and at this point it should be already marked.
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu1x2+ -p tcp --sport 80 -j nbu1x2-2
#    - ingress coming from NI2
#    - TODO: should every app automatically get access to all portmaps in the same network?
#            Currently this is inconsistent. Apps whose drop-all rule precede this will not get implicit access to port maps.
iptables -A PREROUTING -t mangle -i br2 -d 192.168.0.2 -p tcp --dport 8080 -j nbu1x2-2
#    - ingress coming from zedbox/outside
iptables -A PREROUTING -t mangle -i veth2.1 -d ${veth_net_prefix}.6 -p tcp --dport 8080 -j nbu1x2-2
# - NI2: drop the rest
configure_mark_and_accept_chain drop-all-nbu1x2 0x2ffffff
iptables -A PREROUTING -t mangle -i br2 -m physdev --physdev-in nbu1x2+ -j drop-all-nbu1x2

# - NI2: portmap 8080:80
#    - coming to zedbox from outside:
iptables -A PREROUTING -t nat -i eth0 -d 192.168.0.2 -p tcp --dport 8080 -j DNAT --to-destination ${veth_net_prefix}.6:8080
#    - coming to zedbox NS from NI1 (hairpin allowed here because NI1 and NI2 networks use the same uplink):
iptables -A PREROUTING -t nat -i veth1 -d 192.168.0.2 -p tcp --dport 8080 -j DNAT --to-destination ${veth_net_prefix}.6:8080
#    - coming to NI2 through bridge:
iptables -A PREROUTING -t nat -i br2 -d 192.168.0.2 -p tcp --dport 8080 -j DNAT --to-destination $(get_app_ip app2 nbu1x2.1):80
#    - coming to NI2 through veth:
iptables -A PREROUTING -t nat -i veth2.1 -d ${veth_net_prefix}.6 -p tcp --dport 8080 -j DNAT --to-destination $(get_app_ip app2 nbu1x2.1):80


# App3 ACLs
# ---------
# - NI3: allow DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain proto-nbu1x3-6 0x6
iptables -A PREROUTING -t mangle -i br3 -m physdev --physdev-in nbu1x3+ -d 10.10.1.1 -p udp -m multiport --dports bootps,domain -j proto-nbu1x3-6
configure_mark_and_accept_chain proto-nbu1x3-7 0x7
iptables -A PREROUTING -t mangle -i br3 -m physdev --physdev-in nbu1x3+ -d 10.10.1.1 -p tcp --dport domain -j proto-nbu1x3-7
configure_mark_and_accept_chain proto-nbu1x3-8 0x8
iptables -A PREROUTING -t mangle -i br3 -m physdev --physdev-in nbu1x3+ -d 169.254.169.254 -p tcp --dport http -j proto-nbu1x3-8
# - NI3: allow all (0.0.0.0/0)
configure_mark_and_accept_chain nbu1x3-1 0x3000001
iptables -A PREROUTING -t mangle -i br3 -m physdev --physdev-in nbu1x3+ -d 0.0.0.0/0 -j nbu1x3-1
# - NI3: drop the rest
configure_mark_and_accept_chain drop-all-nbu1x3 0x3ffffff
iptables -A PREROUTING -t mangle -i br3 -m physdev --physdev-in nbu1x3+ -j drop-all-nbu1x3


# App4 ACLs
# ---------
# - NI4: allow DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain proto-nbu1x4-6 0x6
iptables -A PREROUTING -t mangle -i br4 -m physdev --physdev-in nbu1x4+ -d 10.10.10.1 -p udp -m multiport --dports bootps,domain -j proto-nbu1x4-6
configure_mark_and_accept_chain proto-nbu1x4-7 0x7
iptables -A PREROUTING -t mangle -i br4 -m physdev --physdev-in nbu1x4+ -d 10.10.10.1 -p tcp --dport domain -j proto-nbu1x4-7
configure_mark_and_accept_chain proto-nbu1x4-8 0x8
iptables -A PREROUTING -t mangle -i br4 -m physdev --physdev-in nbu1x4+ -d 169.254.169.254 -p tcp --dport http -j proto-nbu1x4-8
# - NI4: allow fport=80 (TCP)
configure_mark_and_accept_chain nbu1x4-1 0x4000001
iptables -A PREROUTING -t mangle -i br4 -m physdev --physdev-in nbu1x4+ -d 0.0.0.0/0 -p tcp --dport 80 -j nbu1x4-1
# - NI4: drop the rest
configure_mark_and_accept_chain drop-all-nbu1x4 0x4ffffff
iptables -A PREROUTING -t mangle -i br4 -m physdev --physdev-in nbu1x4+ -j drop-all-nbu1x4


# App5 ACLs
# ---------
# - NI5: allow DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain proto-nbu1x5-6 0x6
iptables -A PREROUTING -t mangle -i br5 -m physdev --physdev-in nbu1x5+ -d 10.10.10.1 -p udp -m multiport --dports bootps,domain -j proto-nbu1x5-6
configure_mark_and_accept_chain proto-nbu1x5-7 0x7
iptables -A PREROUTING -t mangle -i br5 -m physdev --physdev-in nbu1x5+ -d 10.10.10.1 -p tcp --dport domain -j proto-nbu1x5-7
configure_mark_and_accept_chain proto-nbu1x5-8 0x8
iptables -A PREROUTING -t mangle -i br5 -m physdev --physdev-in nbu1x5+ -d 169.254.169.254 -p tcp --dport http -j proto-nbu1x5-8
# - NI5: allow fport=80 (TCP)
configure_mark_and_accept_chain nbu1x5-1 0x5000001
iptables -A PREROUTING -t mangle -i br5 -m physdev --physdev-in nbu1x5+ -d 0.0.0.0/0 -p tcp --dport 80 -j nbu1x5-1
# - NI5: drop the rest
configure_mark_and_accept_chain drop-all-nbu1x5 0x5ffffff
iptables -A PREROUTING -t mangle -i br5 -m physdev --physdev-in nbu1x5+ -j drop-all-nbu1x5


# App6 ACLs
# ---------
# - (switch) NI6 - ingress direction: allow ingress DNS, BOOTP, cloud-init HTTP
iptables -A FORWARD -t filter -o eth3 -m physdev --physdev-out nbu1x6+ -p udp -m multiport --sports bootps,domain -j ACCEPT
iptables -A FORWARD -t filter -o eth3 -m physdev --physdev-out nbu1x6+ -p tcp --sport domain -j ACCEPT
# - (switch) NI6 - ingress direction: allow 192.168.0.0/16 but limit to 5/s, bursts of 15
#     - TODO: this one is weird, why not to use --physdev-out?
iptables -A FORWARD -t filter -i eth3 -o eth3 -s 192.168.0.0/16 -m limit --limit 5/sec --limit-burst 15 -j ACCEPT
# - (switch) NI6 - ingress direction: block the rest
iptables -A FORWARD -t filter -o eth3 -m physdev --physdev-out nbu1x6+ -j DROP

# - (switch) NI6 - egress direction: allow ingress DNS, BOOTP, cloud-init HTTP
iptables -A PREROUTING -t raw -i eth3 -m physdev --physdev-in nbu1x6+ -p udp -m multiport --dports bootps,domain -j ACCEPT
iptables -A PREROUTING -t raw -i eth3 -m physdev --physdev-in nbu1x6+ -p tcp --dport domain -j ACCEPT
# - (switch) NI6 - egress direction: allow 192.168.0.0/16 but limit to 5/s, bursts of 15
iptables -A PREROUTING -t raw -i eth3 -m physdev --physdev-in nbu1x6+ -d 192.168.0.0/16 -m limit --limit 5/sec --limit-burst 15 -j ACCEPT
# - (switch) NI6 - egress direction: block the rest
iptables -A PREROUTING -t raw -i eth3 -m physdev --physdev-in nbu1x6+ -j DROP

# - (switch) NI6 - mark DNS, BOOTP, cloud-init HTTP
configure_mark_and_accept_chain proto-eth3-nbu1x6-6 0x6
iptables -A PREROUTING -t mangle -i eth3 -m physdev --physdev-in nbu1x6+ -d 192.168.3.1 -p udp -m multiport --dports bootps,domain -j proto-eth3-nbu1x6-6
configure_mark_and_accept_chain proto-eth3-nbu1x6-7 0x7
iptables -A PREROUTING -t mangle -i eth3 -m physdev --physdev-in nbu1x6+ -d 192.168.3.1 -p tcp --dport domain -j proto-eth3-nbu1x6-7
configure_mark_and_accept_chain proto-eth3-nbu1x6-8 0x8
iptables -A PREROUTING -t mangle -i eth3 -m physdev --physdev-in nbu1x6+ -d 169.254.169.254 -p tcp --dport http -j proto-eth3-nbu1x6-8
# - (switch) NI6 - mark dst=192.168.0.0/16 (ACE) in both directions
configure_mark_and_accept_chain eth3-nbu1x6-1 0x6000001
iptables -A PREROUTING -t mangle -i eth3 -m physdev --physdev-in nbu1x6+ -d 192.168.0.0/16 -j eth3-nbu1x6-1
# TODO: why not to use --physdev-out?
iptables -A PREROUTING -t mangle -i eth3 -s 192.168.0.0/16 -j eth3-nbu1x6-1
# Note: dropped flows are not marked for switch networks


# Allow EVE to initiate communication with apps.
configure_mark_and_accept_chain eve-veth1 0xa
iptables -A PREROUTING -t mangle -i veth1.1 -s ${veth_net_prefix}.1 -j eve-veth1
configure_mark_and_accept_chain eve-veth2 0xa
iptables -A PREROUTING -t mangle -i veth2.1 -s ${veth_net_prefix}.5 -j eve-veth2
configure_mark_and_accept_chain eve-veth3 0xa
iptables -A PREROUTING -t mangle -i veth3.1 -s ${veth_net_prefix}.9 -j eve-veth3
configure_mark_and_accept_chain eve-veth4 0xa
iptables -A PREROUTING -t mangle -i veth4.1 -s ${veth_net_prefix}.13 -j eve-veth4
configure_mark_and_accept_chain eve-veth5 0xa
iptables -A PREROUTING -t mangle -i veth5.1 -s ${veth_net_prefix}.17 -j eve-veth5

# Remaining common rules.
# Special mark for ICMP
iptables -A PREROUTING -t mangle -p icmp -j CONNMARK --set-mark 0x9
# Mark (and drop) whatever is left unmarked.
mark_remaining_traffic