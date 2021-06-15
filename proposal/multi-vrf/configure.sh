#!/usr/bin/env bash

set -x

# Add link to a given container network namespace under /var/run/netns of another container.
# expose_container_netns <container-to-expose> <container-where-the-link-is-added>
function expose_container_netns() {
  # Get the process ID for the container named ${1}:
  local pid=$(docker inspect -f '{{.State.Pid}}' "${1}")

  # Make the container's network namespace available to the ip-netns command:
  docker exec ${2} mkdir -p /var/run/netns
  docker exec ${2} ln -sf /proc/${pid}/ns/net "/var/run/netns/${1}"
}

# Expose network namespaces between containers.
declare -a containers=("gw" "zedbox" "app1" "app2" "app3" "app4")

for expose_cont in "${containers[@]}"
do
  for in_cont in "${containers[@]}"
  do
    expose_container_netns $expose_cont $in_cont
  done
done

# Configure uplink interfaces between zedbox and GW.
docker exec gw /scripts/uplinks.sh

# Configure dnsmasq inside GW to provide DNS (and DHCP) services for the switch network.
docker exec gw /scripts/external_dns.sh

# Configure local network instances (without downlinks and ACLs for now).
# Args:                        <ni-index> <ni-subnet>    <br-ipnet>     <dhcp-range>                   <uplink>
docker exec zedbox /scripts/local_ni.sh 1 10.10.1.0/24   10.10.1.1/24   10.10.1.50,10.10.1.150,60m     eth0
docker exec zedbox /scripts/local_ni.sh 2 192.168.1.0/24 192.168.1.1/24 192.168.1.50,192.168.1.150,60m eth0
docker exec zedbox /scripts/local_ni.sh 3 10.10.1.0/24   10.10.1.1/24   10.10.1.50,10.10.1.150,60m     eth1

# Configure downlink interfaces between apps and network instances.
docker exec app1 /scripts/downlink.sh  nbu1x1 br1  nbu2x1 br2
docker exec app2 /scripts/downlink.sh  nbu1x2 br2
docker exec app3 /scripts/downlink.sh  nbu1x3 br3
docker exec app4 /scripts/downlink.sh  nbu1x4 eth2

# Configure static DNS entries
docker exec zedbox /scripts/hosts.sh 1 app1 nbu1x1.1
docker exec zedbox /scripts/hosts.sh 2 app1 nbu2x1.1
docker exec zedbox /scripts/hosts.sh 2 app2 nbu1x2.1
docker exec zedbox /scripts/hosts.sh 3 app3 nbu1x3.1

# Configure policy based routing inside the zedbox network namespace for local network instances.
# Args:                   <ni-index> <uplink-index> <uplink-subnet> <uplink-ip> <uplink-broadcast> <gw-ip>
docker exec zedbox /scripts/pbr.sh 1  0             192.168.0.0/24  192.168.0.2 192.168.0.255      192.168.0.1
docker exec zedbox /scripts/pbr.sh 2  0             192.168.0.0/24  192.168.0.2 192.168.0.255      192.168.0.1
docker exec zedbox /scripts/pbr.sh 3  1             192.168.1.0/24  192.168.1.2 192.168.1.255      192.168.1.1
