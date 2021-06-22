# EVE networking experiments

This repo is used to test new network configurations for [EVE OS](https://github.com/lf-edge/eve)
using docker containers to simulate different network stacks and CLI tools to make configuration changes.
The purpose is to quickly and easily validate proposed network configuration changes before commencing any
implementation work in the EVE repository.

Developed and tested on Ubuntu 20.04.

## Scenario

The EdgeDevice JSON configuration corresponding to this scenario can be found [here](./scenario.json).\
This is the simplest scenario I could think of that covers all important aspects of networking in EVE OS:

- edge device has 3 uplink interfaces: `eth0`, `eth1`, `eth2`
- 4 network instances are created:
    - local network `NI1`, using `eth0` as uplink (in the moment which is being simulated here)
    - local network `NI2`, also using `eth0` as uplink
    - local network `NI3`, using `eth1` as uplink
    - switch network `NI4`, bridged with `eth2`
- 4 applications are deployed:
    - `app1` connected to `NI1` and `NI2`
        - it runs HTTP server on the local port `80`
    - `app2` connected to `NI2`
        - it runs HTTP server on the local port `80`
    - `app3` connected to `NI3`
    - `app4` connected to `NI4`
- there is a `GW` container simulating the router to which the edge device is connected
    - for simplicity, in this simulation all uplinks are connected to the same router
    - `GW` runs dnsmasq as an (eve-external) DNS+DHCP service for the switch network `NI4`
        - i.e. this is the DHCP server that will allocate IP address for `app4`
    - `GW` container is connected to the host via docker bridge with NAT
        - this gives apps the access to the Internet
- there is `zedbox` container representing the default network namespace of EVE OS
    - in multi-ns proposal there is also one container per local network instance
- the simulated ACLs are configured as follows:
    - `app1`:
        - able to access `*github.com`
        - able to access `app2` http server:
            - either directly via `NI2` (`eidset` rule with `fport=80`)
            - or hairpinning: `NI1` -> `zedbox` namespace (using portmap) -> `NI2`
                - i.e. without leaving the edge node (note that this should be allowed because `NI1` an `NI2` use the same uplink)
                - not sure what the `ACCEPT` ACE should look like in this case - statically configured uplink subnet(s)?
    - `app2`:
        - http server is exposed on the uplink IP and port `8080`
        - is able to access `eidset`/`fport=80` - which means it can talk to `app1` http server
    - `app3`:
        - is able to communicate with any IPv4 endpoint
    - `app4`:
        - is able to access `app2` by hairpinning outside the box
            - this is however limited to 5 packets per second with bursts up to 15 packets
- IP subnets of `NI1` and `NI3` are identical (separation via namespaces or VRFs is necessary)
- IP subnets of `NI2` and that of the uplink `eth1` are identical (separation via namespaces or VRFs is necessary)

## Proposals

* [Multiple network namespaces](./MULTI-NS.md)
* [Multiple VRFs / CT zones](./MULTI-VRF.md)
