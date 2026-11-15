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
| `10.100.1.0/24` | agents | MCP and agent VMs, untrusted: mcp `.11`, rea `.12`, mcp-web `.13` (modules/services/mcp/README.md) |
| `10.100.2.0/24` | apps | everything else serving something: partdb `.10`, paperless `.11`, inventree `.12` |
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

The router's config, its rules and names live in [Altirix/Mikrotik](https://github.com/Altirix/Mikrotik): the
export, and a patch per change. Every zone's policy and every rule a service README names (`labs: edge to ...`) is
there.
