#!/usr/bin/env bash

set -x

# This script is run from an app container.
# It is used to configure downlink VETH interfaces connecting the app with network instances.
#
# Usage: ./downlink.sh [<veth-name> <bridge-name>]...


while (( "$#" )); do

veth=${1}
bridge_name=${2}

ip link add name ${veth} type veth peer name ${veth}.1
ip link set ${veth} netns zedbox
ip link set ${veth}.1 up
ip netns exec zedbox ip link set ${veth} up
ip netns exec zedbox ip link set dev ${veth} master ${bridge_name}

dhclient -v ${veth}.1
cat /etc/resolv.conf.dhclient-new.* > /etc/resolv.conf
echo "options rotate" >> /etc/resolv.conf

shift 2
done