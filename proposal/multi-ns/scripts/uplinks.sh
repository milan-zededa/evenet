#!/usr/bin/env bash

set -x

# This script is run from the GW container.
# It is used to configure VETH interfaces connecting zedbox with GW (simulating uplink interfaces).

# gw0 <-> keth0 <-> eth0
ip link add name gw0 type veth peer name keth0
ip link set keth0 netns zedbox
ip link set gw0 up
ip addr add 192.168.0.1/24 dev gw0
ip netns exec zedbox ip link set keth0 up
ip netns exec zedbox ip link add name eth0 type bridge
ip netns exec zedbox ip link set dev eth0 up
ip netns exec zedbox ip link set dev keth0 master eth0
ip netns exec zedbox ip addr add 192.168.0.2/24 dev eth0
# - instead of using DHCP, configure default route statically in this simulation
# - this default route is for zedbox only, NIs use PBR
ip netns exec zedbox ip route add default via 192.168.0.1 dev eth0 src 192.168.0.2 metric 206

# gw1 <-> keth1 <-> eth1
ip link add name gw1 type veth peer name keth1
ip link set keth1 netns zedbox
ip link set gw1 up
ip netns exec zedbox ip link set keth1 up
ip addr add 192.168.1.1/24 dev gw1
ip netns exec zedbox ip link set keth1 up
ip netns exec zedbox ip link add name eth1 type bridge
ip netns exec zedbox ip link set dev eth1 up
ip netns exec zedbox ip link set dev keth1 master eth1
ip netns exec zedbox ip addr add 192.168.1.2/24 dev eth1
# - instead of using DHCP, configure default route statically in this simulation
# - this default route is for zedbox only, NIs use PBR
ip netns exec zedbox ip route add default via 192.168.1.1 dev eth1 src 192.168.1.2 metric 207

# gw2 <-> keth2 <-> eth2
ip link add name gw2 type veth peer name keth2
ip link set keth2 netns zedbox
ip link set gw2 up
ip netns exec zedbox ip link set keth2 up
ip addr add 192.168.2.1/24 dev gw2
ip netns exec zedbox ip link set keth2 up
ip netns exec zedbox ip link add name eth2 type bridge
ip netns exec zedbox ip link set dev eth2 up
ip netns exec zedbox ip link set dev keth2 master eth2
ip netns exec zedbox ip addr add 192.168.2.2/24 dev eth2
# - instead of using DHCP, configure default route statically in this simulation
# - this default route is for zedbox only, NIs use PBR
ip netns exec zedbox ip route add default via 192.168.2.1 dev eth2 src 192.168.2.2 metric 208

# gw3 <-> keth3 <-> eth3
ip link add name gw3 type veth peer name keth3
ip link set keth3 netns ni6
ip link set gw3 up
ip netns exec ni6 ip link set keth3 up
ip addr add 192.168.3.1/24 dev gw3
ip netns exec ni6 ip link set keth3 up
ip netns exec ni6 ip link add name eth3 type bridge
ip netns exec ni6 ip link set dev eth3 up
ip netns exec ni6 ip link set dev keth3 master eth3
ip netns exec ni6 ip addr add 192.168.3.2/24 dev eth3

# gw <-> host
iptables -t nat -A POSTROUTING -o eth0 -s 192.168.0.0/24 -j MASQUERADE
iptables -t nat -A POSTROUTING -o eth0 -s 192.168.1.0/24 -j MASQUERADE
iptables -t nat -A POSTROUTING -o eth0 -s 192.168.2.0/24 -j MASQUERADE
iptables -t nat -A POSTROUTING -o eth0 -s 192.168.3.0/24 -j MASQUERADE
