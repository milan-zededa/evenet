#!/usr/bin/env bash

set -x

# This script is run from the zedbox container.
# It is used to configure policy-based routing for a network instance inside the zedbox network namespace.
#
# Usage: pbr.sh <ni-index> <ni-type> <uplink-index> <veth-subnet> <uplink-subnet> <zedbox-veth-ip> <ni-veth-ip> <veth-broadcast> <uplink-ip> <uplink-broadcast> <gw-ip>

ni_index=${1}
ni_veth="veth${ni_index}.1"
zedbox_veth="veth${ni_index}"
ni_type=${2}

uplink_index=${3}
uplink="eth${uplink_index}"

veth_subnet=${4}
uplink_subnet=${5}

zedbox_veth_ip=${6}
ni_veth_ip=${7}
veth_broadcast=${8}
uplink_ip=${9}
uplink_broadcast=${10}
gw_ip=${11}


# Routing:
#  app -> <ni-namespace-main-table> -> VETH+SNAT -> <uplink-table> -> SNAT -> external
#
#  external -> DNAT -> <local-table> -> VETH+DNAT -> <ni-namespace-main-table> -> app
#
#  EVE -> <eve-table> -> VETH -> <ni-namespace-main-table> -> app -> <ni-namespace-main-table> -> VETH -> <uplink-table> -> EVE


# Destinations available to all network instances using the given uplink interface.
# It includes the uplink interface, but not any other mgmt interface. Traffic destined to non-uplink mgmt
# interfaces should leave the box.
if [ "$ni_type" = "local" ]; then
  # Share table between local NIs with the same uplink interface
  uplink_table=$((500+uplink_index))
else
  # VPN (PBR not used for switch NI)
  # Isolate VPN network from other NIs.
  uplink_table=$((550+ni_index))
fi

# Table used by EVE to talk to apps in this NI.
eve_table=$((600+ni_index))

# Table priorities
#
# Priority of the uplink table.
pbr_uplink_table_prio=1000
# Priority of the eve table.
pbr_eve_table_prio=2000
# IP rule priority for the original local table
pbr_orig_local_prio=10000


function cut_mask() {
  echo ${1} | cut -d'/' -f1
}

# IP rules
# - original local routing table
#   - make sure that this has lower priority then per-NI tables, so that traffic destined to mgmt interface which
#     is not uplink for the given source app is hairpinned outside the box
ip rule del from all lookup local
ip rule add priority ${pbr_orig_local_prio} from all lookup local
# - uplink table
ip rule add priority ${pbr_uplink_table_prio} iif ${zedbox_veth} lookup ${uplink_table}
# - eve table
ip rule add priority ${pbr_eve_table_prio} from ${zedbox_veth_ip}/32 lookup ${eve_table}
ip rule add priority ${pbr_eve_table_prio} oif ${zedbox_veth} lookup ${eve_table}

# Uplink table
# - veth
ip route add table ${uplink_table} broadcast $(cut_mask ${veth_subnet}) dev ${zedbox_veth} scope link src ${zedbox_veth_ip}
ip route add table ${uplink_table} local ${zedbox_veth_ip} dev ${zedbox_veth} scope host src ${zedbox_veth_ip}
ip route add table ${uplink_table} broadcast ${veth_broadcast} dev ${zedbox_veth} scope link src ${zedbox_veth_ip}
ip route add table ${uplink_table} ${veth_subnet} dev ${zedbox_veth} scope link src ${zedbox_veth_ip}
# - uplink
ip route add table ${uplink_table} broadcast $(cut_mask ${uplink_subnet}) dev ${uplink} scope link src ${uplink_ip}
ip route add table ${uplink_table} local ${uplink_ip} dev ${uplink} scope host src ${uplink_ip}
ip route add table ${uplink_table} broadcast ${uplink_broadcast} dev ${uplink} scope link src ${uplink_ip}
ip route add table ${uplink_table} ${uplink_subnet} dev ${uplink} scope link src ${uplink_ip}
# - default
ip route add table ${uplink_table} default via ${gw_ip} dev ${uplink}

# EVE table
# - veth
ip route add table ${eve_table} broadcast $(cut_mask ${veth_subnet}) dev ${zedbox_veth} scope link src ${zedbox_veth_ip}
ip route add table ${eve_table} local ${zedbox_veth_ip} dev ${zedbox_veth} scope host src ${zedbox_veth_ip}
ip route add table ${eve_table} broadcast ${veth_broadcast} dev ${zedbox_veth} scope link src ${zedbox_veth_ip}
ip route add table ${eve_table} ${veth_subnet} dev ${zedbox_veth} scope link src ${zedbox_veth_ip}
# - default
ip route add table ${eve_table} default via ${ni_veth_ip} dev ${zedbox_veth}