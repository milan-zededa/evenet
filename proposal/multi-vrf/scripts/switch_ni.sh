#!/usr/bin/env bash

set -x

# This script is run from the zedbox container.
# It is used to finalize configuration of a switch network (CT zone).
#
# Usage: switch_ni.sh <ni-index> <downlink-interface> <uplink-interface>

ni_index=${1}
dowlink=${2}
uplink=${3}

iptables -t raw -A PREROUTING -i ${dowlink} -j CT --zone ${ni_index}
iptables -t raw -A OUTPUT -o ${dowlink} -j CT --zone ${ni_index}
iptables -t raw -A PREROUTING -i ${uplink} -j CT --zone ${ni_index}
iptables -t raw -A OUTPUT -o ${uplink} -j CT --zone ${ni_index}