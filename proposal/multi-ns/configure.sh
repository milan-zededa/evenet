#!/usr/bin/env bash

set -x

# Network subnet which should not collide with anything.
# Also experimented with 127.0.0.0/8 and 0.0.0.0/8 but it didn't work and behave very strangely.
veth_net_prefix=169.254.100

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
declare -a containers=("gw" "cloud1" "cloud2" "zedbox" "ni1" "ni2" "ni3" "ni4" "ni5" "ni6" "app1" "app2" "app3" "app4" "app5" "app6")
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

# Configure clouds.
docker exec cloud1 /scripts/cloud.sh 1
docker exec cloud2 /scripts/cloud.sh 2

# Configure local/vpn network instances (without downlinks and ACLs for now).
# Args:               <ni-index> <ni-subnet>    <br-ipnet>     <dhcp-range>                   <zedbox-veth-ipnet>      <ni-veth-ipnet>          <uplink>
docker exec ni1 /scripts/ni.sh 1 10.10.1.0/24   10.10.1.1/24   10.10.1.50,10.10.1.150,60m     ${veth_net_prefix}.1/30  ${veth_net_prefix}.2/30  eth0
docker exec ni2 /scripts/ni.sh 2 192.168.1.0/24 192.168.1.1/24 192.168.1.50,192.168.1.150,60m ${veth_net_prefix}.5/30  ${veth_net_prefix}.6/30  eth0
docker exec ni3 /scripts/ni.sh 3 10.10.1.0/24   10.10.1.1/24   10.10.1.50,10.10.1.150,60m     ${veth_net_prefix}.9/30  ${veth_net_prefix}.10/30 eth1
docker exec ni4 /scripts/ni.sh 4 10.10.10.0/24  10.10.10.1/24  10.10.10.50,10.10.10.150,60m   ${veth_net_prefix}.13/30 ${veth_net_prefix}.14/30 eth1
docker exec ni5 /scripts/ni.sh 5 10.10.10.0/24  10.10.10.1/24  10.10.10.50,10.10.10.150,60m   ${veth_net_prefix}.17/30 ${veth_net_prefix}.18/30 eth2

# Configure and start strongSwan for VPN network instances.
docker exec ni4 /scripts/vpn_ni.sh ${veth_net_prefix}.14 192.168.111.1 10.10.10.0/24 192.168.0.0/24
docker exec ni5 /scripts/vpn_ni.sh ${veth_net_prefix}.18 192.168.222.1 10.10.10.0/24 192.168.0.0/24

# Configure downlink interfaces between apps and network instances.
docker exec app1 /scripts/downlink.sh  nbu1x1 ni1 br  nbu2x1 ni2 br
docker exec app2 /scripts/downlink.sh  nbu1x2 ni2 br
docker exec app3 /scripts/downlink.sh  nbu1x3 ni3 br
docker exec app4 /scripts/downlink.sh  nbu1x4 ni4 br
docker exec app5 /scripts/downlink.sh  nbu1x5 ni5 br
docker exec app6 /scripts/downlink.sh  nbu1x6 ni6 eth3

# Configure static DNS entries
docker exec ni1 /scripts/hosts.sh app1 nbu1x1.1
docker exec ni2 /scripts/hosts.sh app1 nbu2x1.1
docker exec ni2 /scripts/hosts.sh app2 nbu1x2.1
docker exec ni3 /scripts/hosts.sh app3 nbu1x3.1
docker exec ni4 /scripts/hosts.sh app4 nbu1x4.1
docker exec ni5 /scripts/hosts.sh app5 nbu1x5.1

# Configure policy based routing inside the zedbox network namespace for local/vpn network instances.
# Args:                   <ni-index> <ni-type> <uplink-index> <veth-subnet>            <uplink-subnet> <zedbox-veth-ip>      <ni-veth-ip>          <veth-broadcast>      <uplink-ip> <uplink-broadcast> <gw-ip>
docker exec zedbox /scripts/pbr.sh 1 local     0              ${veth_net_prefix}.0/30  192.168.0.0/24  ${veth_net_prefix}.1  ${veth_net_prefix}.2  ${veth_net_prefix}.3  192.168.0.2 192.168.0.255      192.168.0.1
docker exec zedbox /scripts/pbr.sh 2 local     0              ${veth_net_prefix}.4/30  192.168.0.0/24  ${veth_net_prefix}.5  ${veth_net_prefix}.6  ${veth_net_prefix}.7  192.168.0.2 192.168.0.255      192.168.0.1
docker exec zedbox /scripts/pbr.sh 3 local     1              ${veth_net_prefix}.8/30  192.168.1.0/24  ${veth_net_prefix}.9  ${veth_net_prefix}.10 ${veth_net_prefix}.11 192.168.1.2 192.168.1.255      192.168.1.1
docker exec zedbox /scripts/pbr.sh 4 vpn       1              ${veth_net_prefix}.12/30 192.168.1.0/24  ${veth_net_prefix}.13 ${veth_net_prefix}.14 ${veth_net_prefix}.15 192.168.1.2 192.168.1.255      192.168.1.1
docker exec zedbox /scripts/pbr.sh 5 vpn       2              ${veth_net_prefix}.16/30 192.168.2.0/24  ${veth_net_prefix}.17 ${veth_net_prefix}.18 ${veth_net_prefix}.19 192.168.2.2 192.168.2.255      192.168.2.1

# Configure ACLs using iptables.
docker exec zedbox /scripts/acls.sh ${veth_net_prefix}