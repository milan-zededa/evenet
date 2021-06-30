# EVE networking experiments

This repo is used to test new network configurations for [EVE OS](https://github.com/lf-edge/eve)
using docker containers to simulate different network stacks and CLI tools to make configuration changes.
The purpose is to quickly and easily validate proposed network configuration changes before commencing any
implementation work in the EVE repository.

Developed and tested on Ubuntu 20.04.

## Scenario

The EdgeDevice JSON configuration corresponding to this scenario can be found [here](./scenario.json).\
This is the simplest scenario we could think of that covers all important aspects of networking in EVE OS:

- edge device has 4 uplink interfaces: `eth0`, `eth1`, `eth2`, `eth3`
- 6 network instances are created:
    - local network `NI1`, using `eth0` as uplink (in the moment which is being simulated here)
    - local network `NI2`, also using `eth0` as uplink
    - local network `NI3`, using `eth1` as uplink
    - vpn network `NI4`, using `eth1` as uplink
    - vpn network `NI5`, using `eth2` as uplink
    - switch network `NI6`, bridged with `eth3`
- 6 applications are deployed:
    - `app1` connected to `NI1` and `NI2`
        - it runs HTTP server on the local port `80`
    - `app2` connected to `NI2`
        - it runs HTTP server on the local port `80`
    - `app3` connected to `NI3`
    - `app4` connected to `NI4`
    - `app5` connected to `NI5`
    - `app6` connected to `NI6`
- there is a `GW` container, simulating the router to which the edge device is connected
    - for simplicity, in this simulation all uplinks are connected to the same router
    - `GW` runs dnsmasq as an (eve-external) DNS+DHCP service for the switch network `NI5`
        - i.e. this is the DHCP server that will allocate IP address for `app5`
    - `GW` container is connected to the host via docker bridge with NAT
        - this gives apps the access to the Internet
- there is a `zedbox` container, representing the default network namespace of EVE OS
    - in multi-ns proposal there is also one container per local network instance
- remote clouds are represented by `cloud1` and `cloud2` containers
    - in both clouds there is an HTTP server running on port `80`
    - VPN network `NI4` is configured to open IPsec tunnel to `cloud1`
    - VPN network `NI5` is configured to open IPsec tunnel to `cloud2`
- the simulated ACLs are configured as follows:
    - `app1`:
        - able to access `*github.com`
        - able to access `app2` http server:
            - either directly via `NI2` (`eidset` rule with `fport=80 (TCP)`)
            - or hairpinning: `NI1` -> `zedbox` namespace (using portmap) -> `NI2`
                - i.e. without leaving the edge node (note that this should be allowed because `NI1` an `NI2` use the same uplink)
                - not sure what the `ACCEPT` ACE should look like in this case - statically configured uplink subnet(s)?
    - `app2`:
        - http server is exposed on the uplink IP and port `8080`
        - is able to access `eidset`/`fport=80 (TCP)` - which means it can talk to `app1` http server
    - `app3`:
        - is able to communicate with any IPv4 endpoint
    - `app4`:
        - is able to access any endpoint (on the cloud) listening on the HTTP port `80` (TCP)
    - `app5`:
        - is able to access any endpoint (on the cloud) listening on the HTTP port `80` (TCP)
    - `app6`:
        - is able to access `app2` by hairpinning outside the box
            - this is however limited to 5 packets per second with bursts up to 15 packets
- (1) IP subnets of `NI1` and `NI3` are identical
- (2) IP subnets of `NI2` and that of the uplink `eth1` are identical
- (3) IP subnets of the remote cloud networks and that of the uplink `eth0` are identical
- (4) Traffic selectors of IPsec tunnels `NI4<->cloud1` and `NI5<->cloud2` are identical

(1)(2)(3)(4) Because of all that, the separation of NIs via namespaces or VRFs is necessary.

## Proposals

* [Multiple network namespaces](./MULTI-NS.md)
* [Multiple VRFs / CT zones](./MULTI-VRF.md)
