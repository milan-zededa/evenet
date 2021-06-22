#!/usr/bin/env bash

set -x

# This script is run from the zedbox container.
# It is used to configure policy-based routing for a network instance inside the zedbox network namespace.
#
# Usage: pbr.sh <ni-index> <uplink-index> <veth-subnet> <uplink-subnet> <zedbox-veth-ip> <ni-veth-ip> <veth-broadcast> <uplink-ip> <uplink-broadcast> <gw-ip>

ni_index=${1}
vrf_name="vrf${ni_index}"
br_name="br${ni_index}"
ni_veth="veth${ni_index}.1"
zedbox_veth="veth${ni_index}"

uplink_index=${2}
uplink="eth${uplink_index}"

veth_subnet=${3}
uplink_subnet=${4}

zedbox_veth_ip=${5}
ni_veth_ip=${6}
veth_broadcast=${7}
uplink_ip=${8}
uplink_broadcast=${9}
gw_ip=${10}


# Routing:
#  app -> <vrf-table> -> VETH+SNAT -> <uplink-table> -> external
#
#  external -> <uplink-table> -> VETH+DNAT -> <vrf-table> -> app
#
#  EVE -> <eve-table> -> VETH -> <vrf-table> -> app -> <vrf-table> -> VETH -> <eve-table> -> EVE


# (Zone=<NI-index>) routing table automatically created and assigned to a VRF device.
vrf_table=$((400+ni_index))

# (Zone=999) Destinations available to all network instances using the given uplink interface.
# It includes the uplink interface, but not any other mgmt interface. Traffic destined to non-uplink mgmt
# interfaces should leave the box.
uplink_table=$((500+uplink_index))

# (Zone=999) table used by EVE to talk to apps in this NI.
eve_table=$((600+ni_index))

# Table priorities
# Note: VRF table has priority 1000
#
# Priority of the uplink table.
pbr_uplink_table_prio=2000
# Priority of the eve table.
pbr_eve_table_prio=3000
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
ip rule add priority ${pbr_uplink_table_prio} iif ${uplink} lookup ${uplink_table}
# - eve table
ip rule add priority ${pbr_eve_table_prio} from ${zedbox_veth_ip}/32 lookup ${eve_table}
ip rule add priority ${pbr_eve_table_prio} oif ${zedbox_veth} lookup ${eve_table}


# VRF table
# (bridge routes are automatically added)
# - default
ip route add table ${vrf_table} default via ${zedbox_veth_ip} dev ${ni_veth}
# - do not use any other routing table for this VRF
ip route add table ${vrf_table} unreachable default metric 4278198272

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
