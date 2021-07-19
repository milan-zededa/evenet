#!/usr/bin/env bash

set -x

# This script is run from an app container.
# It is used to configure downlink TAP interfaces connecting the app with network instances.
#
# Usage: ./downlink_tap.sh [<ni-index> <tap-name> <bridge-name>]...


while (( "$#" )); do

  ni_index=${1}
  tap=${2}
  bridge_name=${3}

  ip tuntap add mode tap ${tap}
  ip link set ${tap} up
  until ip link | grep " ${tap}:" | grep -q LOWER_UP;
  do
    echo "Waiting for qemu to connect to the TAP interface (${tap})..."
    sleep 3
  done

  ip link set ${tap} netns zedbox
  ip netns exec zedbox ip link set ${tap} up
  ip netns exec zedbox ip link set dev ${tap} master ${bridge_name}

  # TODO: this does not really help to avoid DNS replies not being properly "zoned" (issue specific to udp?):
  #
  # udp      17 28 src=10.10.1.1 dst=10.10.1.94 sport=53 dport=37925 [UNREPLIED] src=10.10.1.94 dst=10.10.1.1 sport=37925 dport=53 mark=0 use=1
  # udp      17 28 src=192.168.1.1 dst=192.168.1.102 sport=53 dport=37925 [UNREPLIED] src=192.168.1.102 dst=192.168.1.1 sport=37925 dport=53 mark=0 use=1
  # udp      17 28 src=192.168.1.102 dst=192.168.1.1 sport=37925 dport=53 src=192.168.1.1 dst=192.168.1.102 sport=53 dport=37925 [ASSURED] mark=9 zone=2 use=1
  # udp      17 28 src=10.10.1.94 dst=10.10.1.1 sport=37925 dport=53 src=10.10.1.1 dst=10.10.1.94 sport=53 dport=37925 [ASSURED] mark=6 zone=1 use=1
  ip netns exec zedbox iptables -t raw -A PREROUTING -i ${tap} -j CT --zone ${ni_index}
  ip netns exec zedbox iptables -t raw -A OUTPUT -o ${tap} -j CT --zone ${ni_index}

  shift 3
done