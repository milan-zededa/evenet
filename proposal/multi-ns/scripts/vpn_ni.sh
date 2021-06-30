#!/usr/bin/env bash

set -x

# This script is run from network instance container.
# It is a follow-up to ni.sh for VPN networks - it configures and starts strongSwan.
#
# Usage: vpn_ni.sh <ni-veth-ip> <cloud-ip> <ni-subnet> <cloud-subnet>
ni_veth_ip=${1}
cloud_ip=${2}
ni_subnet=${3}
cloud_subnet=${4}

mkdir -p /etc/swanctl
cat <<EOF > /etc/swanctl/swanctl.conf
connections {
   gw {
      version = 2
      mobike = no
      proposals = aes256-sha1-modp2048
      local_addrs  = ${ni_veth_ip}
      remote_addrs = ${cloud_ip}

      local-1 {
         auth = psk
      }
      remote-1 {
         auth = psk
      }
      children {
         gw {
            local_ts = ${ni_subnet}
            remote_ts = ${cloud_subnet}
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

supervisorctl reread
supervisorctl update

sleep 2
max_attempts=10
for i in $(seq $max_attempts); do
  swanctl --load-all && break
  sleep 2
done

# Exclude traffic that matches an IPsec policy from getting NATed.
iptables -t nat -I POSTROUTING -m policy --pol ipsec --dir out -j ACCEPT