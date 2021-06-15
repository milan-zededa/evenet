#!/usr/bin/env bash

set -x

# This script is run from the zedbox container.
# It is used to configure policy-based routing for a network instance inside the zedbox network namespace.
#
# Usage: pbr.sh <ni-index> <uplink-index> <veth-subnet> <uplink-subnet> <zedbox-veth-ip> <ni-veth-ip> <veth-broadcast> <uplink-ip> <uplink-broadcast> <gw-ip>

ni_index=${1}
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

zedbox_veth="veth${ni_index}"

# IP rule priority for packets destined to local interfaces
pbr_local_prio=9999
# IP rule priority for packets destined to internet coming from apps
pbr_out_prio=10000
# IP rule priority for external packets coming in towards apps
pbr_in_prio=11000
# IP rule priority for packets from EVE to apps
pbr_internal_prio=12000
# IP rule priority for the original local table
pbr_orig_local_prio=13000

# Local/Link destinations available to all network instances using the given uplink interface.
# It includes the uplink interface, but not any other mgmt interface. Traffic destined to non-uplink mgmt
# interfaces should leave the box.
uplink_local_table=$((400+uplink_index))

# NI-specific table (this could be actually per-uplink table)
# - in EVE table-index = 500 + <bridge-interface-index>
# - for this simulation we will do: 500 + <ni-index>
# - but in the actual proposal there is: 500 + <veth-interface-index>
ni_table=$((500+ni_index))

# Table used by EVE to talk to apps in this NI.
# This is newly introduced by this proposal.
eve_table=$((700+ni_index))

function cut_mask() {
  echo ${1} | cut -d'/' -f1
}

# IP rule
# - original local routing table
#   - make sure that this has lower priority then per-NI tables, so that traffic destined to mgmt interface which
#     is not uplink for the given source app is hairpinned outside the box
ip rule del from all lookup local
ip rule add priority ${pbr_orig_local_prio} from all lookup local
# - local destination + broadcast + link
ip rule add priority ${pbr_local_prio} from ${ni_veth_ip}/32 lookup ${uplink_local_table}
ip rule add priority ${pbr_local_prio} to ${ni_veth_ip}/32 lookup ${uplink_local_table}
# - from application to outside
ip rule add priority ${pbr_out_prio} from ${ni_veth_ip}/32 lookup ${ni_table}
# - from outside to application
ip rule add priority ${pbr_in_prio} to ${ni_veth_ip}/32 lookup ${ni_table}
# - from EVE to application
ip rule add priority ${pbr_local_prio} from ${zedbox_veth_ip}/32 lookup ${uplink_local_table}
ip rule add priority ${pbr_local_prio} oif ${zedbox_veth} lookup ${uplink_local_table}
ip rule add priority ${pbr_internal_prio} from ${zedbox_veth_ip}/32 lookup ${eve_table}
ip rule add priority ${pbr_internal_prio} oif ${zedbox_veth} lookup ${eve_table}

# Local/Link uplink table
# - veth
ip route add table ${uplink_local_table} broadcast $(cut_mask ${veth_subnet}) dev ${zedbox_veth} scope link src ${zedbox_veth_ip}
ip route add table ${uplink_local_table} local ${zedbox_veth_ip} dev ${zedbox_veth} scope host src ${zedbox_veth_ip}
ip route add table ${uplink_local_table} broadcast ${veth_broadcast} dev ${zedbox_veth} scope link src ${zedbox_veth_ip}
ip route add table ${uplink_local_table} ${veth_subnet} dev ${zedbox_veth} scope link src ${zedbox_veth_ip}
# - uplink
ip route add table ${uplink_local_table} broadcast $(cut_mask ${uplink_subnet}) dev ${uplink} scope link src ${uplink_ip}
ip route add table ${uplink_local_table} local ${uplink_ip} dev ${uplink} scope host src ${uplink_ip}
ip route add table ${uplink_local_table} broadcast ${uplink_broadcast} dev ${uplink} scope link src ${uplink_ip}
ip route add table ${uplink_local_table} ${uplink_subnet} dev ${uplink} scope link src ${uplink_ip}

# NI<->outside routing table
ip route add table ${ni_table} default via ${gw_ip} dev ${uplink}

# EVE<->NI routing table
ip route add table ${eve_table} default via ${ni_veth_ip} dev ${zedbox_veth}
