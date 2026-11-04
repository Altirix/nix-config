# Networking

## labs (VLAN 100)

Where incus instances live. labs only reaches the router: instance ports are isolated
(`security.port_isolation`), VMs talk to each other through the router or directly over labs-mesh. The
hypervisors never talk to or route for it (`services/incus/config/instance-isolation.nft`).

Every address is a pinned /32 routed through the router, so the /24 a VM sits in is its trust zone: router
rules name zones, not hosts. Same VLAN, same bridge, a zone is only an address range.

| Range | Zone | For |
|---|---|---|
| `10.100.0.0/24` | shared | the router (`10.100.0.1`) and what every VM may reach on its ports: auth `.10`, logs `.11`. They open nothing themselves |
| `10.100.1.0/24` | agents | MCP and agent VMs, untrusted: mcp `.11`, rea-dynamic `.12` (modules/services/mcp/README.md, Router) |
| `10.100.2.0/24` | apps | everything else serving something: partdb `.10` |
| `10.100.3.0/24` | work | VMs you work in (Windows, vGPU guests, dev boxes), home reaches every port |
| `10.100.4.0/24`-`10.100.254.0/24` | | free, e.g. Kubernetes nodes |
| `10.100.255.0/24` | | unused: the router's old DHCP pool, nothing on labs can take a lease (below) |

A zone only means something if a VM can't pick its address. Every labs NIC filters what it sends to the address
pinned to its instance (`security.ipv4_filtering`/`ipv6_filtering`, `labsNic` in `modules/compute.nix`), and labs
has no DHCP in incus, so an instance without a pin can't send IPv4 or IPv6 at all. Changing the address inside a
VM, root or not, only cuts it off. Turn the router's DHCP server for VLAN 100 off, nothing can use it.

The work zone, home in on every port (the rest of labs only gets ssh and RDP):

```routeros
/ip firewall filter
add chain=forward action=accept connection-state=new in-interface="VLAN 10 HomeNet" dst-address=10.100.3.0/24 comment="labs: home to work" place-before=[find comment="labs: only home and tunnel in"]
```

The shared zone's VMs open nothing but NTP (`networking.timeServers` in `modules/virtual.nix`, by address so it needs
no DNS: Kanidm's tokens and passkeys depend on the clock), so one that's taken can't reach the internet, the router,
home or another VM. Their deploys push the whole closure (no `--use-substitutes`). At the top; the holes
(`labs: shared time`, `labs: logs in`, `labs: edge to auth`) are added after, so they sit above:

```routeros
/ip firewall filter
add chain=input action=drop connection-state=new src-address=10.100.0.2-10.100.0.254 comment="labs: shared opens nothing" place-before=0
add chain=forward action=drop connection-state=new src-address=10.100.0.2-10.100.0.254 comment="labs: shared opens nothing" place-before=0
add chain=forward action=accept connection-state=new src-address=10.100.0.2-10.100.0.254 dst-address=162.159.200.1,162.159.200.123 protocol=udp dst-port=123 comment="labs: shared time" place-before=0
```

Their journals still reach logs: `labs: logs in` sits above this.

Every VM that needs a network sets `homelab.labs.address` (a /32 with the router on-link). The hypervisors then
pin that IP to the incus instance of the same name (profile `<name>`), the only address it can send from. Deploy
the hypervisors, then the VM (until then it has no network). Instances that aren't hosts of this flake (Windows,
vGPU guests) go in `otherAddresses` in `modules/compute.nix` and set the address themselves.

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
