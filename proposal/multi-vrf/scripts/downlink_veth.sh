#!/usr/bin/env bash

set -x

# This script is run from an app container.
# It is used to configure downlink VETH interfaces connecting the app with network instances.
#
# Usage: ./downlink_veth.sh [<ni-index> <veth-name> <bridge-name>]...


while (( "$#" )); do
  ni_index=${1}
  veth=${2}
  bridge_name=${3}

  ip link add name ${veth} type veth peer name ${veth}.1
  ip link set ${veth} netns zedbox
  ip link set ${veth}.1 up
  ip netns exec zedbox ip link set ${veth} up
  ip netns exec zedbox ip link set dev ${veth} master ${bridge_name}

  # TODO: this does not really help to avoid DNS replies not being properly "zoned" (issue specific to udp?):
  #
  # udp      17 28 src=10.10.1.1 dst=10.10.1.94 sport=53 dport=37925 [UNREPLIED] src=10.10.1.94 dst=10.10.1.1 sport=37925 dport=53 mark=0 use=1
  # udp      17 28 src=192.168.1.1 dst=192.168.1.102 sport=53 dport=37925 [UNREPLIED] src=192.168.1.102 dst=192.168.1.1 sport=37925 dport=53 mark=0 use=1
  # udp      17 28 src=192.168.1.102 dst=192.168.1.1 sport=37925 dport=53 src=192.168.1.1 dst=192.168.1.102 sport=53 dport=37925 [ASSURED] mark=9 zone=2 use=1
  # udp      17 28 src=10.10.1.94 dst=10.10.1.1 sport=37925 dport=53 src=10.10.1.1 dst=10.10.1.94 sport=53 dport=37925 [ASSURED] mark=6 zone=1 use=1
  ip netns exec zedbox iptables -t raw -A PREROUTING -i ${veth} -j CT --zone ${ni_index}
  ip netns exec zedbox iptables -t raw -A OUTPUT -o ${veth} -j CT --zone ${ni_index}

  dhclient -v ${veth}.1
  cat /etc/resolv.conf.dhclient-new.* > /etc/resolv.conf
  echo "options rotate" >> /etc/resolv.conf

  shift 3
done