# Multi-NS Proposal

## Diagram

![Multi-NS Diagram](./diagrams/evenet-multi-ns.png)

## Source code

See `proposal/multi-ns` sub-directory.

## Deploy & Test

Deploy simulation of the scenario with per-NI network namespaces:
```
$ make start-multi-ns
```

Check that `app1` has been assigned IP addresses in both networks:
```
$ docker exec -it app1 bash
root@6ba02e9464c0:/# ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
2: nbu1x1.1@if5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether c6:c5:7d:09:41:30 brd ff:ff:ff:ff:ff:ff link-netns ni1
    inet 10.10.1.66/24 brd 10.10.1.255 scope global dynamic nbu1x1.1
       valid_lft 3513sec preferred_lft 3513sec
4: nbu2x1.1@if5: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000
    link/ether e6:53:75:fc:3a:45 brd ff:ff:ff:ff:ff:ff link-netns ni2
    inet 192.168.1.64/24 brd 192.168.1.255 scope global dynamic nbu2x1.1
       valid_lft 3513sec preferred_lft 3513sec
```

Try `github.com` (should be ALLOWED) and `google.com` (should be BLOCKED) from `app1`:
```
$ docker exec -it app1 bash
root@6ba02e9464c0:/# curl github.com; echo $?
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

Check conntrack for the allowed connection (also notice that SNAT on the veth interface is being used here):
```
$ docker exec -it ni1 bash
root@559d039a1383:/# conntrack -L
tcp      6 117 TIME_WAIT src=10.10.1.121 dst=140.82.121.3 sport=42458 dport=80 src=140.82.121.3 dst=169.254.100.2 sport=80 dport=42458 [ASSURED] mark=16777217 use=1
```

Check that conntrack was created even for the dropped connection:
```
$ docker exec -it ni1 bash
root@559d039a1383:/# conntrack -L
tcp      6 118 SYN_SENT src=10.10.1.121 dst=216.58.212.174 sport=57916 dport=80 [UNREPLIED] src=216.58.212.174 dst=10.10.1.121 sport=80 dport=57916 mark=33554431 use=1
...
```

Check that `app1` can access `app2` in the shared network `ni2`:
```
$ docker exec -it app1 bash
root@6ba02e9464c0:/# curl --interface nbu2x1.1 app2; echo $?
...
0
```

Note that `eidset` was applied in this case:
```
$ docker exec -it ni2 bash
root@99669d7cb66c:/# iptables -L -v -t mangle
Chain PREROUTING (policy ACCEPT 0 packets, 0 bytes)
 pkts bytes target     prot opt in     out     source               destination
  ...         
   43  2320 nbu2x1-1   tcp  --  br     any     anywhere             anywhere             PHYSDEV match --physdev-in nbu2x1+ match-set ipv4.eids.nbu2x1 dst tcp dpt:http
  ...
```

Conntrack is created even in this case:
```
$ docker exec -it ni2 bash
root@99669d7cb66c:/# conntrack -L
tcp      6 8 CLOSE src=192.168.1.149 dst=192.168.1.67 sport=50972 dport=80 src=192.168.1.67 dst=192.168.1.149 sport=80 dport=50972 [ASSURED] mark=16777217 use=1
```

Try to hairpin from `app1` to `app2` via portmap in the zedbox namespace:
```
$ docker exec -it app1 bash
root@8d44d3f125e1:/# curl --interface nbu1x1.1 192.168.0.2:8080
...
```

See conntrack in the zedbox ns for this connection:
```
$ docker exec -it zedbox bash
root@896f9f7ab86d:/# conntrack -L
tcp      6 87 TIME_WAIT src=169.254.100.2 dst=192.168.0.2 sport=59286 dport=8080 src=169.254.100.6 dst=169.254.100.2 sport=8080 dport=59286 [ASSURED] mark=0 use=1
```

Try to hairpin from `app1` to `app2` via portmap in the `NI2` namespace:
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

Try any website from `app3`:
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
*Note*: in this case the traffic is SNATed when it is leaving zedbox NS and entering NI2 NS, otherwise there would be
an IP address collision (between the source IP address and the NI2 subnet) - notice `... src=169.254.100.6 dst=169.254.100.5 ...`:
```
$ docker exec -it zedbox bash
root@69a8da04c4f3:/# conntrack -L
tcp      6 118 TIME_WAIT src=169.254.100.10 dst=192.168.0.2 sport=55370 dport=8080 src=192.168.0.2 dst=192.168.1.2 sport=8080 dport=55370 [ASSURED] mark=0 use=1
tcp      6 118 TIME_WAIT src=192.168.1.2 dst=192.168.0.2 sport=55370 dport=8080 src=169.254.100.6 dst=169.254.100.5 sport=8080 dport=55370 [ASSURED] mark=0 use=1
conntrack v1.4.5 (conntrack-tools): 2 flow entries have been shown.

```

Try to hairpin from `app4` to `app2` via portmap outside the edge device (verify with `docker exec -it gw tcpdump -i any -n`):
```
$ docker exec -it app4 bash
root@8d44d3df421:/# curl 192.168.0.2:8080
(WORKS AND IT IS LIMITED IN BANDWIDTH)
```

Try any remote destination from `app4`. Should be blocked and leave no conntracks:
```
$ docker exec -it app4 bash
root@6ba02e9464c0:/# curl --connect-timeout 3 --retry 3  google.com
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
**TODO**: DNS service for the zedbox namespace with app host entries?

Try to connect to `app2` from outside over the portmap:
```
$ docker exec -it gw bash
root@4cb6b997b2be:/# curl 192.168.0.2:8080; echo $?
...
0
```

Finally, undeploy simulation with:
```
$ make stop-multi-ns
```