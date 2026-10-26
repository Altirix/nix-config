# MCP

`homelab.mcp.servers` runs MCP servers for agents, each as its own `mcp-<name>` unit and port. stdio servers
sit behind mcp-proxy: streamable HTTP on `http://<host>:<port>/mcp`, SSE on `/sse`. Nothing authenticates, so
the router decides who reaches which port (Router), and only the edge's nginx (with tokens) puts the low-risk
ones on the internet (From outside). The VMs open every port they serve: a firewall on a VM is gone
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

`nix build .#checks.x86_64-linux.mcp` boots the servers `hosts/virtual/mcp` enables in a VM and calls each from
a client over the network, see `tests/mcp.nix`.

## Router (MikroTik)

Everything that keeps the mcp VM apart is on the router, so it holds with root lost on the VM. The hypervisors
pin the VM to its address (`security.ipv4_filtering`, networking/README.md), so the router's `src-address`
matches can't be spoofed from labs. Never give `mcp` the `labs-mesh` profile: VXLAN goes VM to VM past the
router.

Who gets in. These go before `labs: only home and tunnel in`, after `labs: home ssh, rdp` (ssh from home still
reaches it for deploys). The edge is its tunnel address `10.0.0.1`, and only on the ports
`hosts/edge/ionos-de/mcp.nix` routes:

```routeros
/ip firewall address-list
add list=mcp-vms address=10.100.1.11 comment="mcp"

/ip firewall filter
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.1.11 protocol=tcp dst-port=8102,8104-8107,8109 comment="labs: edge to mcp" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=drop connection-state=new in-interface=wg-vpn dst-address-list=mcp-vms comment="labs: tunnel to mcp vms, nothing else" place-before=[find comment="labs: only home and tunnel in"]
```

Agents on the LAN that should reach the servers directly (every port on `mcp`, including playwright and github),
one per machine, also before `labs: tunnel to mcp vms, nothing else`:

```routeros
/ip firewall filter
add chain=forward action=accept connection-state=new src-address=<agent> dst-address=10.100.1.11 protocol=tcp dst-port=8100-8199 comment="labs: agents to mcp" place-before=[find comment="labs: tunnel to mcp vms, nothing else"]
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
`/ip firewall filter print stats where comment~"mcp"`: the edge's 502s with
`labs: tunnel to mcp vms, nothing else` counting mean a port missing from `labs: edge to mcp`. If the router
ever masquerades into labs, the edge arrives as `10.100.0.1` instead of `10.0.0.1` and every edge rule misses.

## From outside

`hosts/edge/ionos-de/mcp.nix` serves nixos, context7, fetch, time, memory and markitdown at
`https://mcp.peacocks.me/<server>/mcp`, proxied over the tunnel (streamable
HTTP only, SSE is deprecated). playwright runs code, github holds a token, they get no route. Every
request needs `Authorization: Bearer <token>`, one token per client in `hosts/edge/ionos-de/secrets.yaml` so each
can be revoked, and the access log names the client. The router only lets the edge's tunnel
address `10.0.0.1` in on the exposed servers' ports (`labs: edge to mcp`, Router), so a compromised edge still
doesn't reach the others. Never add a wireguard forward to `10.100.1.11`: forwards arrive from `10.0.0.1`
too and would skip the token. Exposing another server takes both, `servers` in `mcp.nix` and its port
in `labs: edge to mcp`.

Set it up: point an A record for `mcp.peacocks.me` at the VPS (ACME needs it before the first deploy), add a
token per client named in `mcp.nix` (`openssl rand -hex 32`), add the router rules (Router), deploy `mcp`, then
`ionos-de`. ionos-de doesn't build with the tokens missing.

```sh
sops hosts/edge/ionos-de/secrets.yaml   # mcp-token-cloud: <hex>
```

Revoke one by removing it from `clients` in `mcp.nix` and from `hosts/edge/ionos-de/secrets.yaml`, rotate one by
editing the secret alone (nginx reloads on deploy). Check from anywhere:

```sh
curl -i https://mcp.peacocks.me/time/mcp -H "Authorization: Bearer $MCP_TOKEN" \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"0"}}}'
```

Claude Code on a laptop, per server:

```sh
claude mcp add --transport http time https://mcp.peacocks.me/time/mcp --header "Authorization: Bearer $MCP_TOKEN"
```

Or in a repo's `.mcp.json`, reading the token from the environment when Claude Code starts:

```json
{
  "mcpServers": {
    "nixos": {
      "type": "http",
      "url": "https://mcp.peacocks.me/nixos/mcp",
      "headers": { "Authorization": "Bearer ${MCP_TOKEN}" }
    },
    "time": {
      "type": "http",
      "url": "https://mcp.peacocks.me/time/mcp",
      "headers": { "Authorization": "Bearer ${MCP_TOKEN}" }
    }
  }
}
```

Claude Code cloud sessions read the same `.mcp.json` from the repo they run in. In the cloud environment's
settings, allow `mcp.peacocks.me` under Network access (Allowed domains, or Full), and add the `cloud` token
as a network secret for `mcp.peacocks.me` so the agent proxy adds `Authorization: Bearer <token>` outside the VM
and the token never reaches the session. Leave out the `headers` then. That the proxy injects it for MCP traffic
isn't documented, so check after deploy that requests show up as `cloud` in `/var/log/nginx/access.log` on
ionos-de. If they arrive as 401, set `MCP_TOKEN` as an environment variable of the environment instead and keep
the `headers` (the session can then read the token).

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
