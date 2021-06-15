#!/usr/bin/env bash

set -x

# This script is run from the zedbox container.
# It is used to configure policy-based routing for a network instance inside the zedbox network namespace.
#
# Usage: pbr.sh <ni-index> <uplink-index> <uplink-subnet> <uplink-ip> <uplink-broadcast> <gw-ip>

ni_index=${1}
vrf_name="vrf${ni_index}"
br_name="br${ni_index}"

uplink_index=${2}
uplink="eth${uplink_index}"

uplink_subnet=${3}
uplink_ip=${4}
uplink_broadcast=${5}
gw_ip=${6}

# IP rule priority for packets destined to local interfaces
# Should have higher priority than:
#  1000:	from all lookup [l3mdev-table]
pbr_local_prio=999
# IP rule priority for external packets coming in towards apps
pbr_in_prio=2000
# IP rule priority for the original local table
pbr_orig_local_prio=10000

# Local/Link uplink destinations available to all network instances using the given uplink interface.
# It includes the uplink interface, but not any other mgmt interface. Traffic destined to non-uplink mgmt
# interfaces should leave the box.
uplink_local_table=$((400+uplink_index))

# NI-specific table (assigned to VRF device)
# - in EVE table-index = 500 + <bridge-interface-index>
# - for this simulation we will do: 500 + <ni-index>
ni_table=$((500+ni_index))

function cut_mask() {
  echo ${1} | cut -d'/' -f1
}

# IP rule
# - original local routing table
#   - make sure that this has lower priority then per-NI tables, so that traffic destined to mgmt interface which
#     is not uplink for the given source app is hairpinned outside the box
ip rule del from all lookup local
ip rule add priority ${pbr_orig_local_prio} from all lookup local
# - uplink (local destination + broadcast + link)
ip rule add priority ${pbr_local_prio} iif ${br_name} lookup ${uplink_local_table}
# - from outside to application
#    TODO: needed ???
ip rule add priority ${pbr_in_prio} fwmark 0x${ni_index}0000/0xff0000 lookup ${ni_table}

# Local/Link uplink table
ip route add table ${uplink_local_table} broadcast $(cut_mask ${uplink_subnet}) dev ${uplink} scope link src ${uplink_ip}
ip route add table ${uplink_local_table} local ${uplink_ip} dev ${uplink} scope host src ${uplink_ip}
ip route add table ${uplink_local_table} broadcast ${uplink_broadcast} dev ${uplink} scope link src ${uplink_ip}
ip route add table ${uplink_local_table} ${uplink_subnet} dev ${uplink} scope link src ${uplink_ip}

# NI<->outside routing table
ip route add table ${ni_table} default via ${gw_ip} dev ${uplink}