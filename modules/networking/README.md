# Networking

## labs (VLAN 100)

Where incus instances live. labs only reaches the router: instance ports are isolated
(`security.port_isolation`), VMs talk to each other through the router or directly over labs-mesh. The
hypervisors never talk to or route for it (`services/incus/config/instance-isolation.nft`).

| Range | For |
|---|---|
| `10.100.0.0/24` | infra (`10.100.0.1` is the router) |
| `10.100.1.0/24`-`10.100.254.0/24` | services, static |
| `10.100.255.0/24` | the router's DHCP pool, only for setup |

A VM that serves something sets `homelab.labs.address` (a /32 with the router on-link). The hypervisors then
pin that IP to the incus instance of the same name (profile `<name>`, `security.ipv4_filtering`), so no other
instance can take it. Deploy the VM, then the hypervisors. Instances that aren't hosts of this flake (Windows)
go in `otherAddresses` in `modules/compute.nix` and set the address themselves.

The router routes VM to VM back out VLAN 100 (no ICMP redirects) and the switch isolates the
hypervisor ports from each other (protected ports), otherwise VMs on different hosts still share L2.

## labs-mesh

A VXLAN overlay across the hypervisors (`homelab.mesh.overlay`), so VMs reach each other directly, e.g. vGPU
guests and `dls`. Opt in with `-p default -p labs-mesh`, the bridge hands out no addresses so each VM sets a
static one in `10.254.0.0/24` (`homelab.labsMesh.address`).

## Router (MikroTik)

labs internet goes out the WireGuard tunnel to the edge, VLAN 10 (home) reaches labs on ssh and RDP only.
The VLAN 100 connection mark only applies to connections labs opens, and replies to home stay in the main table
instead of following labs into the tunnel.

```routeros
/ip firewall mangle
set [find comment="Mark VLAN 100 connections as wg-exit"] connection-state=new

/routing rule
add dst-address=10.10.0.0/24 action=lookup-only-in-table table=main place-before=0 comment="labs: replies to home stay local"

/ip firewall filter
add chain=forward action=accept connection-state=established,related in-interface-list=LABS comment="labs: replies" place-before=[find comment="labs: no connection to private wg ips"]
add chain=forward action=accept connection-state=new in-interface="VLAN 10 HomeNet" out-interface-list=LABS protocol=tcp dst-port=22,3389 comment="labs: home ssh, rdp" place-before=[find comment="labs: no connection to private wg ips"]
add chain=forward action=accept connection-state=new in-interface="VLAN 10 HomeNet" out-interface-list=LABS protocol=udp dst-port=3389 comment="labs: home rdp udp" place-before=[find comment="labs: no connection to private wg ips"]
add chain=forward action=drop connection-state=new out-interface-list=LABS in-interface=!wg-vpn comment="labs: only home and tunnel in" place-before=[find comment="labs: no connection to private wg ips"]
```

Check with `/ip firewall filter print stats where comment~"labs"`: `labs: replies` counting while the
connection hangs means replies are being routed into the tunnel.
