# Multi-VRF Proposal

## Diagram

![Multi-VRF Diagram](./diagrams/evenet-multi-vrf.png)

## Source code

See `proposal/multi-vrf` sub-directory.

## Deploy & Test

Deploy simulation of the scenario with per-NI VRF:
```
$ make start-multi-vrf
```

Check that `app1` has been assigned IP addresses in both networks:
```
$ docker exec -it app1 bash
root@6ba02e9464c0:/# ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: nbu1x1.1@if20: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 46:e9:3b:af:5b:2d brd ff:ff:ff:ff:ff:ff link-netns zedbox
    inet 10.10.1.72/24 brd 10.10.1.255 scope global nbu1x1.1
       valid_lft forever preferred_lft forever
4: nbu2x1.1@if21: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether 16:ad:1e:c5:c6:a6 brd ff:ff:ff:ff:ff:ff link-netns zedbox
    inet 192.168.1.146/24 brd 192.168.1.255 scope global nbu2x1.1
       valid_lft forever preferred_lft forever
```

Try `github.com` (should be ALLOWED) and `google.com` (should be BLOCKED) from `app1`:
```
$ docker exec -it app1 bash
root@6ba02e9464c0:/# curl --interface nbu1x1.1 github.com; echo $?
0
root@6ba02e9464c0:/# curl --interface nbu1x1.1 --connect-timeout 3 --retry 3  google.com
curl: (28) Connection timed out after 3000 milliseconds
Warning: Transient problem: timeout Will retry in 1 seconds. 3 retries left.
curl: (28) Connection timed out after 3000 milliseconds
Warning: Transient problem: timeout Will retry in 2 seconds. 2 retries left.
curl: (28) Connection timed out after 3000 milliseconds
Warning: Transient problem: timeout Will retry in 4 seconds. 1 retries left.
curl: (28) Connection timed out after 3000 milliseconds
```

Check conntracks for the allowed connection. Notice that there are two entries - one in the NI-specific CT zone and
the second one in the common `999` CT zone. Packet is being routed and NATed twice:
```
$ docker exec -it zedbox bash
root@559d039a1383:/# conntrack -L
tcp      6 118 TIME_WAIT src=10.10.1.53 dst=140.82.121.4 sport=40486 dport=80 src=140.82.121.4 dst=169.254.100.2 sport=80 dport=40486 [ASSURED] mark=16777217 zone=1 use=1
tcp      6 118 TIME_WAIT src=169.254.100.2 dst=140.82.121.4 sport=40486 dport=80 src=140.82.121.4 dst=192.168.0.2 sport=80 dport=40486 [ASSURED] mark=0 zone=999 use=1
```

Check that conntrack was created even for dropped connections (in the NI-specific CT zone only where the packet ended at the dummy interface):
```
$ docker exec -it zedbox bash
root@559d039a1383:/# conntrack -L
tcp      6 118 SYN_SENT src=10.10.1.53 dst=216.58.212.174 sport=56562 dport=80 [UNREPLIED] src=216.58.212.174 dst=10.10.1.53 sport=80 dport=56562 mark=33554431 zone=1 use=1
...
```

Check that `app1` can access `app2` in the shared network `NI2`:
```
$ docker exec -it app1 bash
root@6ba02e9464c0:/# curl --interface nbu2x1.1 app2; echo $?
...
0
```

Note that `eidset` was applied in this case:
```
$ docker exec -it zedbox bash
root@99669d7cb66c:/# iptables -L -v -t mangle
Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination
  ...         
   144  7564 nbu2x1-1   tcp  --  br2    any     anywhere             anywhere             PHYSDEV match --physdev-in nbu2x1+ match-set ipv4.eids.nbu2x1 dst tcp dpt:http
  ...
```

Conntrack is created even in this case (NI-zone only, zone `999` is not traversed here):
```
$ docker exec -it zedbox bash
root@99669d7cb66c:/# conntrack -L
tcp      6 115 TIME_WAIT src=192.168.1.113 dst=192.168.1.135 sport=40380 dport=80 src=192.168.1.135 dst=192.168.1.113 sport=80 dport=40380 [ASSURED] mark=16777217 zone=2 use=1
```

Try to hairpin from `app1` to `app2` via portmap inside the zedbox (via zone `999`):
```
$ docker exec -it app1 bash
root@8d44d3f125e1:/# curl --interface nbu1x1.1 192.168.0.2:8080
...
```

There will 3 conntracks for this hairpin - one for `NI1` zone, another for `NI2` zone and finally one for `999` where
DNAT occurred:
```
root@6485105f733a:/# conntrack -L
tcp      6 118 TIME_WAIT src=10.10.1.53 dst=192.168.0.2 sport=55096 dport=8080 src=192.168.0.2 dst=169.254.100.2 sport=8080 dport=55096 [ASSURED] mark=16777218 zone=1 use=1
tcp      6 118 TIME_WAIT src=169.254.100.2 dst=192.168.0.2 sport=55096 dport=8080 src=169.254.100.6 dst=169.254.100.2 sport=8080 dport=55096 [ASSURED] mark=0 zone=999 use=1
tcp      6 118 TIME_WAIT src=169.254.100.2 dst=169.254.100.6 sport=55096 dport=8080 src=192.168.1.135 dst=169.254.100.2 sport=80 dport=55096 [ASSURED] mark=33554434 zone=2 use=1
```

Try to hairpin from `app1` to `app2` via portmap in the `NI2` zone:
```
$ docker exec -it app1 bash
root@8d44d3f125e1:/# ip route del default
root@8d44d3f125e1:/# ip route add default via 192.168.1.1 dev nbu2x1.1
root@8d44d3f125e1:/# curl 192.168.0.2:8080
<BLOCKED>
```
**TODO**: this is blocked - there is no ACE for `app1` allowing this in `NI2`.\
Or should this be implicitly allowed? Currently, EVE is inconsistent here.

Try to access mock HTTP server with cloud-init metadata from `app1`:
```
$ docker exec -it app1 bash
root@8d44d3f125e1:/# curl 169.254.169.254; echo $?
...
0
```

Try to access `app1` & `github.com` from `app2` (should be allowed & blocked, respectively):
```
$ docker exec -it app2 bash
root@c956a4d1c24d:/# curl app1; echo $?
...
0
root@c956a4d1c24d:/# curl --connect-timeout 3 --retry 3  github.com
curl: (28) Connection timed out after 3000 milliseconds
Warning: Transient problem: timeout Will retry in 1 seconds. 3 retries left.
curl: (28) Connection timed out after 3001 milliseconds
Warning: Transient problem: timeout Will retry in 2 seconds. 2 retries left.
curl: (28) Connection timed out after 3001 milliseconds
Warning: Transient problem: timeout Will retry in 4 seconds. 1 retries left.
curl: (28) Connection timed out after 3001 milliseconds
```

Try any website from `app3` (all should be ALLOWED):
```
$ docker exec -it app3 bash
root@604474ae312b:/# curl zededa.com; echo $?
<html>
<head><title>301 Moved Permanently</title></head>
<body>
<center><h1>301 Moved Permanently</h1></center>
<hr><center>nginx</center>
</body>
</html>
0
```

Try to hairpin from `app3` to `app2` via portmap outside the edge device (verify with `docker exec -it gw tcpdump -i any -n`):
```
$ docker exec -it app3 bash
root@8d44d3df421:/# curl 192.168.0.2:8080; echo $?
...
0
```
*Note*: in this case the traffic is SNATed as it is leaving default VRF and entering the NI2 VRF, otherwise there would be
an IP address collision (between the source IP address and the NI2 subnet) - notice `... src=169.254.100.6 dst=169.254.100.5 ...`.

As expected there are 4 conntracks in total for this communication inside the zedbox namespace:
```
tcp      6 104 TIME_WAIT src=10.10.1.94 dst=192.168.0.2 sport=48944 dport=8080 src=192.168.0.2 dst=169.254.100.10 sport=8080 dport=48944 [ASSURED] mark=50331649 zone=3 use=1
tcp      6 104 TIME_WAIT src=169.254.100.10 dst=192.168.0.2 sport=48944 dport=8080 src=192.168.0.2 dst=192.168.1.2 sport=8080 dport=48944 [ASSURED] mark=0 zone=999 use=1
tcp      6 104 TIME_WAIT src=192.168.1.2 dst=192.168.0.2 sport=48944 dport=8080 src=169.254.100.6 dst=169.254.100.5 sport=8080 dport=48944 [ASSURED] mark=0 zone=999 use=1
tcp      6 104 TIME_WAIT src=169.254.100.5 dst=169.254.100.6 sport=48944 dport=8080 src=192.168.1.135 dst=169.254.100.5 sport=80 dport=48944 [ASSURED] mark=33554434 zone=2 use=1
```

Try to establish IPsec tunnel between `NI4` and `cloud1`:
```
$ docker exec zedbox swanctl --initiate --child gw1
[IKE] initiating IKE_SA gw1[1] to 192.168.111.1
[ENC] generating IKE_SA_INIT request 0 [ SA KE No N(NATD_S_IP) N(NATD_D_IP) N(FRAG_SUP) N(HASH_ALG) N(REDIR_SUP) ]
[NET] sending packet: from 169.254.100.13[500] to 192.168.111.1[500] (464 bytes)
[NET] received packet: from 192.168.111.1[500] to 169.254.100.13[500] (472 bytes)
[ENC] parsed IKE_SA_INIT response 0 [ SA KE No N(NATD_S_IP) N(NATD_D_IP) N(FRAG_SUP) N(HASH_ALG) N(CHDLESS_SUP) N(MULT_AUTH) ]
[CFG] selected proposal: IKE:AES_CBC_256/HMAC_SHA1_96/PRF_HMAC_SHA1/MODP_2048
[IKE] local host is behind NAT, sending keep alives
[CFG] no IDi configured, fall back on IP address
[IKE] authentication of '169.254.100.13' (myself) with pre-shared key
[IKE] establishing CHILD_SA gw1{1}
[ENC] generating IKE_AUTH request 1 [ IDi AUTH SA TSi TSr N(MULT_AUTH) N(EAP_ONLY) N(MSG_ID_SYN_SUP) ]
[NET] sending packet: from 169.254.100.13[4500] to 192.168.111.1[4500] (220 bytes)
[NET] received packet: from 192.168.111.1[4500] to 169.254.100.13[4500] (204 bytes)
[ENC] parsed IKE_AUTH response 1 [ IDr AUTH SA TSi TSr ]
[IKE] authentication of '192.168.111.1' with pre-shared key successful
[IKE] IKE_SA gw1[1] established between 169.254.100.13[169.254.100.13]...192.168.111.1[192.168.111.1]
[IKE] scheduling rekeying in 14018s
[IKE] maximum IKE_SA lifetime 15458s
[CFG] selected proposal: ESP:AES_CBC_128/HMAC_SHA1_96/NO_EXT_SEQ
[IKE] CHILD_SA gw1{1} established with SPIs c206b3e3_i ca85eaf8_o and TS 10.10.10.0/24 === 192.168.0.0/24
initiate completed successfully

$ docker exec zedbox swanctl --list-sas
gw1: #1, ESTABLISHED, IKEv2, 46afca5bab3815a7_i* 1fa571683a56e2a6_r
  local  '169.254.100.13' @ 169.254.100.13[4500]
  remote '192.168.111.1' @ 192.168.111.1[4500]
  AES_CBC-256/HMAC_SHA1_96/PRF_HMAC_SHA1/MODP_2048
  established 49s ago, rekeying in 13969s
  gw1: #1, reqid 1, INSTALLED, TUNNEL-in-UDP, ESP:AES_CBC-128/HMAC_SHA1_96
    installed 49s ago, rekeying in 3204s, expires in 3911s
    in  c206b3e3 (-|0x00000004),      0 bytes,     0 packets
    out ca85eaf8 (-|0x00000004),      0 bytes,     0 packets
    local  10.10.10.0/24
    remote 192.168.0.0/24

$ docker exec cloud1 swanctl --list-sas
gw: #1, ESTABLISHED, IKEv2, 46afca5bab3815a7_i 1fa571683a56e2a6_r*
  local  '192.168.111.1' @ 192.168.111.1[4500]
  remote '169.254.100.13' @ 192.168.1.2[4500]
  AES_CBC-256/HMAC_SHA1_96/PRF_HMAC_SHA1/MODP_2048
  established 71s ago, rekeying in 13184s
  gw: #1, reqid 1, INSTALLED, TUNNEL-in-UDP, ESP:AES_CBC-128/HMAC_SHA1_96
    installed 71s ago, rekeying in 3188s, expires in 3889s
    in  ca85eaf8,      0 bytes,     0 packets
    out c206b3e3,      0 bytes,     0 packets
    local  192.168.0.0/24
    remote 10.10.10.0/24
```

Notice that single instance of strongSwan operates for all VPN networks in the CT zone `999`:
```
bash-5.1# conntrack -L
udp      17 26 src=169.254.100.13 dst=192.168.111.1 sport=500 dport=500 src=192.168.111.1 dst=192.168.1.2 sport=500 dport=500 mark=0 zone=999 use=1
udp      17 26 src=169.254.100.13 dst=192.168.111.1 sport=4500 dport=4500 src=192.168.111.1 dst=192.168.1.2 sport=4500 dport=4500 mark=0 zone=999 use=1
```

Try to access HTTP server in `cloud1` from `app4`:
```
$ docker exec -it app4 bash
root@5a911b8522cc:/# curl 192.168.0.1:80; echo $?
...
0
```

In this case, two conntracks are established - one for the unencrypted traffic in the `NI4` zone and the other
for the encrypted traffic in the `999` zone:
```
tcp      6 61 TIME_WAIT src=10.10.10.94 dst=192.168.0.1 sport=47982 dport=80 src=192.168.0.1 dst=10.10.10.94 sport=80 dport=47982 [ASSURED] mark=67108865 zone=4 use=1
udp      17 101 src=169.254.100.13 dst=192.168.111.1 sport=4500 dport=4500 src=192.168.111.1 dst=192.168.1.2 sport=4500 dport=64496 [ASSURED] mark=0 zone=999 use=1
```

Try to establish IPsec tunnel between `NI5` and `cloud2`:
```
$ docker exec zedbox swanctl --initiate --child gw2
[IKE] initiating IKE_SA gw2[2] to 192.168.222.1
[ENC] generating IKE_SA_INIT request 0 [ SA KE No N(NATD_S_IP) N(NATD_D_IP) N(FRAG_SUP) N(HASH_ALG) N(REDIR_SUP) ]
[NET] sending packet: from 169.254.100.17[500] to 192.168.222.1[500] (464 bytes)
[NET] received packet: from 192.168.222.1[500] to 169.254.100.17[500] (472 bytes)
[ENC] parsed IKE_SA_INIT response 0 [ SA KE No N(NATD_S_IP) N(NATD_D_IP) N(FRAG_SUP) N(HASH_ALG) N(CHDLESS_SUP) N(MULT_AUTH) ]
[CFG] selected proposal: IKE:AES_CBC_256/HMAC_SHA1_96/PRF_HMAC_SHA1/MODP_2048
[IKE] local host is behind NAT, sending keep alives
[CFG] no IDi configured, fall back on IP address
[IKE] authentication of '169.254.100.17' (myself) with pre-shared key
[IKE] establishing CHILD_SA gw2{2}
[ENC] generating IKE_AUTH request 1 [ IDi AUTH SA TSi TSr N(MULT_AUTH) N(EAP_ONLY) N(MSG_ID_SYN_SUP) ]
[NET] sending packet: from 169.254.100.17[4500] to 192.168.222.1[4500] (220 bytes)
[NET] received packet: from 192.168.222.1[4500] to 169.254.100.17[4500] (204 bytes)
[ENC] parsed IKE_AUTH response 1 [ IDr AUTH SA TSi TSr ]
[IKE] authentication of '192.168.222.1' with pre-shared key successful
[IKE] IKE_SA gw2[2] established between 169.254.100.17[169.254.100.17]...192.168.222.1[192.168.222.1]
[IKE] scheduling rekeying in 14068s
[IKE] maximum IKE_SA lifetime 15508s
[CFG] selected proposal: ESP:AES_CBC_128/HMAC_SHA1_96/NO_EXT_SEQ
[IKE] CHILD_SA gw2{2} established with SPIs c117176e_i c72b9ea7_o and TS 10.10.10.0/24 === 192.168.0.0/24
initiate completed successfully

$ docker exec zedbox swanctl --list-sas
gw2: #2, ESTABLISHED, IKEv2, d58f27e45404be14_i* 2c315234f13e5f09_r
  local  '169.254.100.17' @ 169.254.100.17[4500]
  remote '192.168.222.1' @ 192.168.222.1[4500]
  AES_CBC-256/HMAC_SHA1_96/PRF_HMAC_SHA1/MODP_2048
  established 26s ago, rekeying in 14042s
  gw2: #2, reqid 2, INSTALLED, TUNNEL-in-UDP, ESP:AES_CBC-128/HMAC_SHA1_96
    installed 26s ago, rekeying in 3241s, expires in 3934s
    in  c117176e (-|0x00000005),      0 bytes,     0 packets
    out c72b9ea7 (-|0x00000005),      0 bytes,     0 packets
    local  10.10.10.0/24
    remote 192.168.0.0/24

$ docker exec cloud2 swanctl --list-sas
gw: #1, ESTABLISHED, IKEv2, d58f27e45404be14_i 2c315234f13e5f09_r*
  local  '192.168.222.1' @ 192.168.222.1[4500]
  remote '169.254.100.17' @ 192.168.2.2[4500]
  AES_CBC-256/HMAC_SHA1_96/PRF_HMAC_SHA1/MODP_2048
  established 43s ago, rekeying in 14080s
  gw: #1, reqid 1, INSTALLED, TUNNEL-in-UDP, ESP:AES_CBC-128/HMAC_SHA1_96
    installed 43s ago, rekeying in 3260s, expires in 3917s
    in  c72b9ea7,      0 bytes,     0 packets
    out c117176e,      0 bytes,     0 packets
    local  192.168.0.0/24
    remote 10.10.10.0/24
```

Try to access HTTP server in `cloud2` from `app5`:
```
$ docker exec -it app5 bash
root@5a911b8522cc:/# curl 192.168.0.1:80; echo $?
...
0
```

In this case, two conntracks are established - one for the unencrypted traffic in the `NI5` zone and the other
for the encrypted traffic in the `999` zone:
```
tcp      6 73 TIME_WAIT src=10.10.10.101 dst=192.168.0.1 sport=45190 dport=80 src=192.168.0.1 dst=10.10.10.101 sport=80 dport=45190 [ASSURED] mark=83886081 zone=5 use=1
udp      17 113 src=169.254.100.17 dst=192.168.222.1 sport=4500 dport=4500 src=192.168.222.1 dst=192.168.2.2 sport=4500 dport=13920 [ASSURED] mark=0 zone=999 use=1
```

Try to hairpin from `app6` to `app2` via portmap outside the edge device:
```
$ docker exec -it app6 bash
root@7b225ce7122:/# curl 192.168.0.2:8080
(WORKS AND IT IS LIMITED IN BANDWIDTH)
```

In this case, there are 3 conntracks inside the zedbox namespace - switch network does not use the `999` zone (but portmap does):
```
tcp      6 299 ESTABLISHED src=192.168.2.86 dst=192.168.0.2 sport=33594 dport=8080 src=192.168.0.2 dst=192.168.2.86 sport=8080 dport=33594 [ASSURED] mark=67108865 zone=4 use=1
tcp      6 299 ESTABLISHED src=192.168.2.86 dst=192.168.0.2 sport=33594 dport=8080 src=169.254.100.6 dst=192.168.2.86 sport=8080 dport=33594 [ASSURED] mark=0 zone=999 use=1
tcp      6 299 ESTABLISHED src=192.168.2.86 dst=169.254.100.6 sport=33594 dport=8080 src=192.168.1.135 dst=192.168.2.86 sport=80 dport=33594 [ASSURED] mark=33554434 zone=2 use=1
```

Try any remote destination from `app6`. Should be blocked and leave no conntracks:
```
$ docker exec -it app6 bash
root@7b225ce7122:/# curl --connect-timeout 3 --retry 3  google.com
curl: (28) Connection timed out after 3000 milliseconds
Warning: Transient problem: timeout Will retry in 1 seconds. 3 retries left.
curl: (28) Connection timed out after 3000 milliseconds
Warning: Transient problem: timeout Will retry in 2 seconds. 2 retries left.
curl: (28) Connection timed out after 3000 milliseconds
Warning: Transient problem: timeout Will retry in 4 seconds. 1 retries left.
curl: (28) Connection timed out after 3000 milliseconds
```

Try to connect from `zedbox` to `app1` (i.e. the case of EVE initiating connection with an app):
```
$ docker exec -it zedbox bash
root@8d44d3df421:/# curl --interface veth1 10.10.1.102:80
...
```
Note that IP address assigned to `app1` may be different for your deployment - get IP with `docker exec app1 ifconfig nbu1x1.1`.\
**TODO**: DNS service for the default VRF with app host entries?

Two conntracks expected in this case:
```
tcp      6 117 TIME_WAIT src=169.254.100.1 dst=10.10.1.53 sport=51096 dport=80 src=10.10.1.53 dst=169.254.100.1 sport=80 dport=51096 [ASSURED] mark=0 zone=999 use=1
tcp      6 117 TIME_WAIT src=169.254.100.1 dst=10.10.1.53 sport=51096 dport=80 src=10.10.1.53 dst=169.254.100.1 sport=80 dport=51096 [ASSURED] mark=10 zone=1 use=1
```

Try to connect to `app2` from outside over the portmap:
```
$ docker exec -it gw bash
root@4cb6b997b2be:/# curl 192.168.0.2:8080; echo $?
...
0
```

Finally, undeploy simulation with:
```
$ make stop-multi-vrf
```
