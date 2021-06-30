#!/usr/bin/env bash

set -x

# This script is run from the cloud{1,2} container.
# It is used to configure VETH interfaces connecting cloud with gw and to start IPsec.
#
# Usage: cloud.sh <cloud-index>

cloud_name=cloud${1}
gw_interface=eth${1}
cloud_subnet=192.168.${1}${1}${1}

# cloud <-> gw
ip link add name eth0 type veth peer name ${gw_interface}
ip link set ${gw_interface} netns gw
ip link set eth0 up
ip addr add ${cloud_subnet}.1/24 dev eth0
ip route add default via ${cloud_subnet}.2 dev eth0
ip netns exec gw ip link set ${gw_interface} up
ip netns exec gw ip addr add ${cloud_subnet}.2/24 dev ${gw_interface}

# loopback for "apps running in the cloud"
ip addr add 192.168.0.1/24 dev lo

# IPsec Gateway
mkdir -p /etc/swanctl
cat <<EOF > /etc/swanctl/swanctl.conf
connections {
   gw {
      version = 2
      mobike = no
      proposals = aes256-sha1-modp2048
      local_addrs  = ${cloud_subnet}.1
      remote_addrs = %any

      local-1 {
         auth = psk
      }
      remote-1 {
         auth = psk
      }
      children {
         gw {
            local_ts = 192.168.0.0/24
            remote_ts = 0.0.0.0/0
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

cat <<EOF > /etc/supervisor.d/ipsec.conf
[program:ipsec]
command=ipsec start --nofork
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF

# http server (representing a service running in the cloud)
cat <<EOF > /etc/supervisor.d/http.conf
[program:http]
command=bash -x /scripts/http.sh ${cloud_name} 80 192.168.0.1
stdout_logfile=/dev/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/dev/fd/2
stderr_logfile_maxbytes=0
EOF


supervisorctl reread
supervisorctl update

sleep 2
max_attempts=10
for i in $(seq $max_attempts); do
  swanctl --load-all && break
  sleep 2
done