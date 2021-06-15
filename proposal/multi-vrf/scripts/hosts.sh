#!/usr/bin/env bash

set -x

# This script is run from the zedbox container.
# It is used to add static DNS entry for an application.
#
# Usage: ./hosts.sh <ni-index> <app> <app-interface>

ni_index=${1}
app=${2}
app_interface=${3}

br_name="br${ni_index}"

IP=$(ip netns exec ${app} ip -f inet addr show ${app_interface} | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')

echo "${IP}  ${app}" > /run/hosts-${br_name}/${app}
