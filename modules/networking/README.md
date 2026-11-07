# Networking

## labs (VLAN 100)

Where incus instances live. labs only reaches the router: instance ports are isolated
(`security.port_isolation`), VMs talk to each other through the router or directly over labs-mesh. The
hypervisors never talk to or route for it (`services/incus/config/instance-isolation.nft`).

Every address is a pinned /32 routed through the router, so the /24 a VM sits in is its trust zone: router
rules name zones, not hosts. Same VLAN, same bridge, a zone is only an address range.

| Range | Zone | For |
|---|---|---|
| `10.100.0.0/24` | shared | the router (`10.100.0.1`) and what every VM may reach on its ports: auth `.10`, logs `.11`, dls `.12`. They open nothing themselves |
| `10.100.1.0/24` | agents | MCP and agent VMs, untrusted: mcp `.11`, rea-dynamic `.12` (modules/services/mcp/README.md, Router) |
| `10.100.2.0/24` | apps | everything else serving something: partdb `.10`, paperless `.11` |
| `10.100.3.0/24` | work | VMs you work in (Windows, vGPU guests, dev boxes), home reaches every port |
| `10.100.4.0/24`-`10.100.254.0/24` | | free, e.g. Kubernetes nodes |
| `10.100.255.0/24` | | unused: the router's old DHCP pool, nothing on labs can take a lease (below) |

A zone only means something if a VM can't pick its address. Every labs NIC filters what it sends to the address
pinned to its instance (`security.ipv4_filtering`/`ipv6_filtering`, `labsNic` in `modules/compute.nix`), and labs
has no DHCP in incus, so an instance without a pin can't send IPv4 or IPv6 at all. Changing the address inside a
VM, root or not, only cuts it off. The router's DHCP server for VLAN 100 is off, nothing could use it.

Each zone's policy is on the router (Router, below): every VM takes its time from the router
(`networking.timeServers` in `modules/virtual.nix`) and may license against dls; home reaches the work zone on every
port and the rest on ssh, RDP and http; the shared zone opens nothing but its logs and its time, so a taken auth or
logs VM can't reach the internet, the router, home or another VM (their deploys push the whole closure, no
`--use-substitutes`); no zone reaches anything private except through those holes; the agents zone is the MCP
README's (modules/services/mcp/README.md).

Every VM that needs a network sets `homelab.labs.address` (a /32 with the router on-link). The hypervisors then
pin that IP to the incus instance of the same name (profile `<name>`), the only address it can send from. Deploy
the hypervisors, then the VM (until then it has no network). Instances that aren't hosts of this flake (Windows,
vGPU guests) go in `otherAddresses` in `modules/compute.nix` and set the address themselves.

The router routes VM to VM back out VLAN 100 (no ICMP redirects) and the switch isolates the
hypervisor ports from each other (protected ports), otherwise VMs on different hosts still share L2.

## labs-mesh

A VXLAN overlay across the hypervisors (`homelab.mesh.overlay`), so VMs reach each other directly, past the router
and every rule on it: only for VMs that trust each other, nothing uses it now. Opt in with `-p default -p labs-mesh`,
the bridge hands out no addresses so each VM sets a static one in `10.254.0.0/24` (`homelab.labsMesh.address`).

## Router (MikroTik)

Everything below `/export` of the RB4011 shows today, and the changes the zones need. labs internet goes out the
WireGuard tunnel to the edge: `labs` (routing table) has only the tunnel, and a rule sends everything from
`10.100.0.0/16` there. Traffic to labs itself, home and mgmt has to stay local, or it bounces off the edge.

The rules every service README names live here, in the order they go: all forward rules just above
`labs: only home and tunnel in`, the time server just above `labs: no router access`.

```routeros
# Lab-to-lab, and replies to mgmt, stay on the router instead of the tunnel (like replies to home already do).
/routing rule
add dst-address=10.100.0.0/16 action=lookup-only-in-table table=main place-before=0 comment="labs: to labs stays local"
add dst-address=10.90.0.0/24 action=lookup-only-in-table table=main place-before=0 comment="labs: replies to mgmt stay local"

# Time, the one thing labs may ask the router for (rea-dynamic opens nothing).
/system ntp client set enabled=yes servers=time.cloudflare.com
/system ntp server set enabled=yes
/ip firewall filter
add chain=input action=accept connection-state=new in-interface-list=LABS src-address=!10.100.1.12 protocol=udp dst-port=123 comment="labs: time from the router" place-before=[find comment="labs: no router access"]

# No DHCP on labs, every NIC is pinned.
/ip dhcp-server disable [find name="VLAN100 - Labs"]
/ip firewall filter disable [find comment="labs: dhcp"]

/ip firewall address-list
add list=log-senders address=10.0.0.1 comment="edge"
add list=log-senders address=10.90.0.0/24 comment="mgmt"
add list=log-senders address=10.10.0.0/24 comment="home"
add list=log-senders address=10.100.0.0/16 comment="labs"
add list=private address=10.0.0.0/8
add list=private address=172.16.0.0/12
add list=private address=192.168.0.0/16
add list=private address=100.64.0.0/10
add list=private address=169.254.0.0/16

# Forward, in this order, each just above "labs: only home and tunnel in".
/ip firewall filter
add chain=forward action=drop   connection-state=new src-address=10.100.1.12 comment="labs: rea-dynamic opens nothing" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new src-address-list=log-senders dst-address=10.100.0.11 protocol=tcp dst-port=9428 comment="labs: logs in" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface="VLAN 10 HomeNet" dst-address=10.100.0.11 protocol=tcp dst-port=9427 comment="labs: home reads logs" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface-list=LABS dst-address=10.100.0.12 protocol=tcp dst-port=443 comment="labs: dls in" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface="VLAN 10 HomeNet" dst-address=10.100.3.0/24 comment="labs: home to work" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface="VLAN 10 HomeNet" protocol=icmp comment="labs: home ping" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.0.10 protocol=tcp dst-port=8443 comment="labs: edge to auth" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.0.11 protocol=tcp dst-port=9427 comment="labs: edge reads logs" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.2.10 protocol=tcp dst-port=80 comment="labs: edge to partdb" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.2.11 protocol=tcp dst-port=80 comment="labs: edge to paperless" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.1.11 protocol=tcp dst-port=8102,8104-8107,8109-8111 comment="labs: edge to mcp" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.1.12 protocol=tcp dst-port=8101 comment="labs: edge to rea-dynamic" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.3.10 protocol=udp dst-port=8000-8010 comment="labs: edge to parsec" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=drop   connection-state=new in-interface=wg-vpn src-address=10.0.0.1 out-interface-list=LABS comment="labs: edge only to its sites" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=drop   connection-state=new in-interface=wg-vpn dst-address=10.100.1.0/24 comment="labs: tunnel to agents, nothing else" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new src-address=10.100.1.11 dst-address=10.100.2.11 protocol=tcp dst-port=8000 comment="labs: mcp to paperless" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=drop   connection-state=new src-address=10.100.0.2-10.100.0.254 comment="labs: shared opens nothing" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=drop   connection-state=new in-interface-list=LABS dst-address-list=private comment="labs: nothing private" place-before=[find comment="labs: only home and tunnel in"]

# Parsec follows Windows-11 into the work zone.
set [find comment="labs: parsec home->vm"] dst-address=10.100.3.10
set [find comment="labs: parsec vm->home"] src-address=10.100.3.10
```

Names: `<host>.mgmt.internal` for the hypervisors and `<instance>.labs.internal` for every labs instance, made from
the hosts' config. Rerun after adding a host or changing an address, it replaces only the entries it made:

```sh
nix eval --raw .#router.dns > dns.rsc
scp dns.rsc admin@10.10.0.1: && ssh admin@10.10.0.1 "/import file-name=dns.rsc"
```

Short names (`ping bode`) need those domains in the client's search list, on Windows (WSL follows it):

```powershell
Set-DnsClientGlobalSetting -SuffixSearchList @("home.internal", "mgmt.internal", "labs.internal")
```

What was already there and stays: the routing rule `labs: replies to home stay local`, `labs: replies`, `labs: home ssh, rdp` (22, 3389, 80), `labs: home rdp udp`, the
Parsec pair, `labs: only home and tunnel in`, `labs: no connection to private wg ips`, `labs: allow tunnel only`
and `labs: no router access`. Other tunnel peers (PCs, phone) still reach labs, except the agents zone.

`labs: nothing private` is what keeps labs off home and mgmt through the edge: the edge routes between its peers,
the router among them, so without it a lab VM reaches `10.10.0.0/24` out the tunnel and back in.

Check with `/ip firewall filter print stats where comment~"labs:"`: `labs: replies` counting while a connection
hangs means replies are being routed into the tunnel (a missing routing rule), an edge site's 502s with
`labs: edge only to its sites` counting mean a port missing from its `labs: edge to` rule.
