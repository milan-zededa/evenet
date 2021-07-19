#!/usr/bin/env bash

set -x

# This script is run from an app container.
# It is used to configure downlink TAP interfaces connecting the app with network instances.
#
# Usage: ./downlink_tap.sh [<tap-name> <ni-namespace> <bridge-name>]...

while (( "$#" )); do
  tap=${1}
  ni_ns=${2}
  bridge_name=${3}

  ip tuntap add mode tap ${tap}
  ip link set ${tap} up
  until ip link | grep " ${tap}:" | grep -q LOWER_UP;
  do
    echo "Waiting for qemu to connect to the TAP interface (${tap})..."
    sleep 3
  done

  ip link set ${tap} netns ${ni_ns}
  ip netns exec ${ni_ns} ip link set ${tap} up
  ip netns exec ${ni_ns} ip link set dev ${tap} master ${bridge_name}

  shift 3
done