#!/usr/bin/env bash

set -x

# This script is run from zedbox container.
# It is a follow-up to ni.sh for NI4 & NI5 - it configures and starts strongSwan for VPN networks.
# In this multi-VRF proposal there is only one StrongSwan instance shared by all VPN network instances with
# potentially overlapping traffic selectors. Using route-based approach with xfrm interfaces it is possible
# to avoid any xfrm-lookup conflicts.
#
# Usage: vpn_nis.sh <veth-net-prefix>
veth_net_prefix=${1}

function add_xfrm_interface() {
  ni_index=${1}
  vrf_name="vrf${ni_index}"
  ni_veth="veth${ni_index}.1"
  vrf_table=$((400+ni_index))

  # XFRM interface
  xfrm_interface=xfrm${ni_index}
  ip link add ${xfrm_interface} type xfrm dev ${ni_veth} if_id ${ni_index}
  ip link set dev ${xfrm_interface} master ${vrf_name}
  ip link set ${xfrm_interface} up

  # select traffic to encrypt
  ip route add 192.168.0.0/24 table ${vrf_table} dev ${xfrm_interface}

  # connection tracking
  iptables -t raw -A PREROUTING -i ${xfrm_interface} -j CT --zone ${ni_index}
  iptables -t raw -A OUTPUT -o ${xfrm_interface} -j CT --zone ${ni_index}
}

add_xfrm_interface 4
add_xfrm_interface 5

# IPsec configuration
mkdir -p /etc/swanctl
cat <<EOF > /etc/swanctl/swanctl.conf
connections {
   gw1 {
      version = 2
      mobike = no
      proposals = aes256-sha1-modp2048
      local_addrs = ${veth_net_prefix}.13
      remote_addrs = 192.168.111.1
      if_id_in = 4
      if_id_out = 4

      local-1 {
         auth = psk
      }
      remote-1 {
         auth = psk
      }
      children {
         gw1 {
            local_ts = 10.10.10.0/24
            remote_ts = 192.168.0.0/24
            esp_proposals = aes128-sha1
         }
      }
   }

   gw2 {
      version = 2
      mobike = no
      proposals = aes256-sha1-modp2048
      local_addrs = ${veth_net_prefix}.17
      remote_addrs = 192.168.222.1
      if_id_in = 5
      if_id_out = 5

      local-1 {
         auth = psk
      }
      remote-1 {
         auth = psk
      }
      children {
         gw2 {
            local_ts = 10.10.10.0/24
            remote_ts = 192.168.0.0/24
            esp_proposals = aes128-sha1
         }
      }
   }
}

secrets {
    ike-1 {
        secret = evenet123
    }
}
EOF

# strongSwan process
cat <<EOF > /etc/supervisor.d/ipsec.conf
[program:ipsec]
command=ipsec start --nofork
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

supervisorctl reread
supervisorctl update

# load IPsec configuration and send it to strongSwan through the VICI interface using swanctl CLI
sleep 2
max_attempts=10
for i in $(seq $max_attempts); do
  swanctl --load-all && break
  sleep 2
done



##### Useful info from the Internet:
#
# https://thermalcircle.de/doku.php?id=blog:linux:nftables_ipsec_packet_flow
#
#
# The location in which strongswan.conf is looked for can be overwritten at start time of the process using libstrongswan
# by setting the STRONGSWAN_CONF environmental variable to the desired location.
#
#
# As suggested, wrapping ipsec commands with this kind of scripts seems to
# work fine:
#
# #!/bin/sh
#
# PREFIX=/var/lib/ipsecns
#
# for file in $PREFIX/$1/{run,etc}; do
#     [ -d $dir ] || exit
# done
#
# mount --bind $PREFIX/$1/run /var/run/
# mount --bind $PREFIX/$1/etc /etc
#
# shift
# eval "$@"
#
# Assuming the above script name is nswrap, just have to use "ip netns exec
# netns_name nswrap netns_name ipsec start", to fire up strongswan.
#
#
# https://wiki.strongswan.org/projects/strongswan/wiki/RouteBasedVPN
#
# XFRM interfaces in VRFs
#
# XFRM interfaces can be associated to a VRF layer 3 master device, so any tunnel terminated by an XFRM interface implicitly is bound to that VRF domain. For example, this allows multi-tenancy setups, where traffic from different tunnels can be separated and routed over different interfaces.
# Due to a limitation in XFRM interfaces, inbound traffic fails policy checking in kernels prior to version 5.1.
#
#
# https://wiki.strongswan.org/issues/2845
#
#
# https://ifstate.net/examples/xfrm-vrf.html

