# MCP

`homelab.mcp.servers` runs MCP servers for agents, each as its own `mcp-<name>` unit and port. stdio servers
sit behind mcp-proxy: streamable HTTP on `http://<host>:<port>/mcp`, SSE on `/sse`. Nothing authenticates, so
the router decides who reaches which port (Router). The VMs open every port they serve: a firewall on a VM is gone
with root on it, so none of what keeps them apart lives there. stdio servers share one process, and with it any
state, between clients. `hosts/virtual/mcp` (`10.100.1.11`) serves them on labs.

Presets in `servers/` only need enabling in the host, anything else is added directly:

```nix
homelab.mcp.servers.sequential-thinking = {
  enable = true;
  command = lib.getExe pkgs.mcp-server-sequential-thinking;
  port = 8100;
};
```

Add it to a client:

```sh
claude mcp add --transport http sequential-thinking http://<host>:8100/mcp
```

## Router (MikroTik)

Everything that keeps the mcp VM apart is on the router, so it holds with root lost on the VM. The hypervisors
pin the VM to its address (`security.ipv4_filtering`, networking/README.md), so the router's `src-address`
matches can't be spoofed from labs. Never give `mcp` the `labs-mesh` profile: VXLAN goes VM to VM past the
router.

Who gets in. Agents on the LAN that should reach the servers, one per machine, before `labs: only home and
tunnel in`, after `labs: home ssh, rdp` (ssh from home still reaches it for deploys):

```routeros
/ip firewall filter
add chain=forward action=accept connection-state=new src-address=<agent> dst-address=10.100.1.11 protocol=tcp dst-port=8100-8199 comment="labs: agents to mcp" place-before=[find comment="labs: only home and tunnel in"]
```

What it opens. `mcp` needs the internet (fetch, context7, playwright, nixos) but nothing private, so fetch and
playwright can't be pointed at home, mgmt, labs or the edge's tunnel address. At the top, ahead of the labs
egress rules:

```routeros
/ip firewall address-list
add list=private address=10.0.0.0/8
add list=private address=172.16.0.0/12
add list=private address=192.168.0.0/16
add list=private address=100.64.0.0/10
add list=private address=169.254.0.0/16

/ip firewall filter
add chain=input action=drop connection-state=new src-address=10.100.1.11 comment="labs: mcp to the internet only" place-before=0
add chain=forward action=drop connection-state=new src-address=10.100.1.11 dst-address-list=private comment="labs: mcp to the internet only" place-before=0
```

The VM uses `1.1.1.1` for DNS, so it needs nothing from the router itself. Check with
`/ip firewall filter print stats where comment~"mcp"`.

## github (8103)

Read-only with one server-side token, so every client reads as its owner. Use a fine-grained PAT with read-only
Contents, Issues, Pull requests and Metadata on the repos it should see (a classic one needs `repo`, which also
allows writes). It lives in the mcp VM's own `hosts/virtual/mcp/secrets.yaml`, so no other host can decrypt
it. The host doesn't build with it enabled and no token.

```sh
sops hosts/virtual/mcp/secrets.yaml   # github-mcp-token: github_pat_...
```

## context7 (8104)

Serves its own `/mcp` (no `/sse`). An API key is optional, per client: `--header "Context7-API-Key: <key>"`.
