#!/usr/bin/env bash

set -x

# This script is run from a network instance container.
# It is used to add static DNS entry for an application.
#
# Usage: ./hosts.sh <app> <app-interface>

app=${1}
app_interface=${2}

IP=$(ip netns exec ${app} ip -f inet addr show ${app_interface} | sed -En -e 's/.*inet ([0-9.]+).*/\1/p')

echo "${IP}  ${app}" > /run/hosts/${app}
