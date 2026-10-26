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

Everything that keeps the MCP VMs apart is on the router, so it holds with root lost on either VM. The
hypervisors pin each VM to its address (`security.ipv4_filtering`, networking/README.md), so the router's
`src-address` matches can't be spoofed from labs. Never give `mcp` or `rea-dynamic` the `labs-mesh` profile:
VXLAN goes VM to VM past the router.

Who gets in. These go before `labs: only home and tunnel in`, after `labs: home ssh, rdp` (ssh from home still
reaches both for deploys). The edge is its tunnel address `10.0.0.1`, and only on the ports
`hosts/edge/ionos-de/mcp.nix` routes:

```routeros
/ip firewall address-list
add list=mcp-vms address=10.100.1.11 comment="mcp"
add list=mcp-vms address=10.100.1.12 comment="rea-dynamic"

/ip firewall filter
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.1.11 protocol=tcp dst-port=8102,8104-8107,8109 comment="labs: edge to mcp" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.1.12 protocol=tcp dst-port=8101 comment="labs: edge to rea-dynamic" place-before=[find comment="labs: only home and tunnel in"]
add chain=forward action=drop connection-state=new in-interface=wg-vpn dst-address-list=mcp-vms comment="labs: tunnel to mcp vms, nothing else" place-before=[find comment="labs: only home and tunnel in"]
```

Agents on the LAN that should reach the servers directly (every port on `mcp`, including playwright and github),
one per machine, also before `labs: tunnel to mcp vms, nothing else`:

```routeros
/ip firewall filter
add chain=forward action=accept connection-state=new src-address=<agent> dst-address=10.100.1.11 protocol=tcp dst-port=8100-8199 comment="labs: agents to mcp" place-before=[find comment="labs: tunnel to mcp vms, nothing else"]
add chain=forward action=accept connection-state=new src-address=<agent> dst-address=10.100.1.12 protocol=tcp dst-port=8101 comment="labs: agents to rea-dynamic" place-before=[find comment="labs: tunnel to mcp vms, nothing else"]
```

What they open. `rea-dynamic` opens nothing, not to the router, labs, home or out the tunnel. `mcp` needs the
internet (fetch, context7, playwright, nixos) but nothing private, so fetch and playwright can't be pointed at
home, mgmt, labs or the edge's tunnel address. Both at the top, ahead of the labs egress rules:

```routeros
/ip firewall address-list
add list=private address=10.0.0.0/8
add list=private address=172.16.0.0/12
add list=private address=192.168.0.0/16
add list=private address=100.64.0.0/10
add list=private address=169.254.0.0/16

/ip firewall filter
add chain=input action=drop connection-state=new src-address=10.100.1.12 comment="labs: rea-dynamic opens nothing" place-before=0
add chain=forward action=drop connection-state=new src-address=10.100.1.12 comment="labs: rea-dynamic opens nothing" place-before=0
add chain=input action=drop connection-state=new src-address=10.100.1.11 comment="labs: mcp to the internet only" place-before=0
add chain=forward action=drop connection-state=new src-address=10.100.1.11 dst-address-list=private comment="labs: mcp to the internet only" place-before=0
```

The `mcp` VM uses `1.1.1.1` for DNS, so it needs nothing from the router itself. If labs ever carries IPv6, the
same holds for v6 or a VM with root egresses over it:

```routeros
/ipv6 firewall filter
add chain=forward action=drop connection-state=new src-address=<rea-dynamic v6> comment="labs: rea-dynamic opens nothing (v6)" place-before=0
add chain=input action=drop connection-state=new src-address=<rea-dynamic v6> comment="labs: rea-dynamic opens nothing (v6)" place-before=0
```

Check with `/ip firewall filter print stats where comment~"mcp|rea-dynamic"`: the edge's 502s with
`labs: tunnel to mcp vms, nothing else` counting mean a port missing from `labs: edge to mcp`. If the router
ever masquerades into labs, the edge arrives as `10.100.0.1` instead of `10.0.0.1` and every edge rule misses.

## From outside

`hosts/edge/ionos-de/mcp.nix` serves nixos, context7, fetch, time, memory and markitdown at
`https://mcp.peacocks.me/<server>/mcp`, proxied over the tunnel (streamable
HTTP only, SSE is deprecated). playwright runs code, github holds a token, they get no route. Every
request needs `Authorization: Bearer <token>`, one token per client in `hosts/edge/ionos-de/secrets.yaml` so each
can be revoked, and the access log names the client. The router only lets the edge's tunnel
address `10.0.0.1` in on the exposed servers' ports (`labs: edge to mcp`, Router), so a compromised edge still
doesn't reach the others. Never add a wireguard forward to `10.100.1.11` or `10.100.1.12`: forwards arrive from
`10.0.0.1` too and would skip the token. Exposing another server takes both, `servers` in `mcp.nix` and its port
in `labs: edge to mcp`.

REA is also routed, `https://mcp.peacocks.me/rea/` → its own VM's nginx `10.100.1.12:8101`, on the same
token. It runs code a caller hands it but reaches nothing (no secrets, the router drops what it opens,
snapshot reset), so a leaked token lands in a dead-end sandbox. That rests on `labs: rea-dynamic opens nothing`
(Router) being live, and covering IPv6 too if labs carries it.

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

## rea (8101)

Decompiles with Ghidra, reads APKs with JADX, runs samples and unpacks firmware. It only runs on
`hosts/virtual/rea-dynamic` (`10.100.1.12`): one supergateway (`rea.service`, `config/rea-gateway.json`) serves
every project in `homelab.mcp.rea.projects` and starts a REA for each MCP session, so agents never close or
replace each other's target; a session idle for 30 minutes ends, and its REA with it. nginx on 8101
(`homelab.mcp.rea.port`, `config/rea-nginx.conf`, reached through the router's `labs: edge to rea-dynamic`) is
the only way in, the gateway (8102) only listens on loopback:

```
https://mcp.peacocks.me/rea/<project>/mcp       the project's server
https://mcp.peacocks.me/rea/<project>/samples/  its uploads, /var/lib/rea/<project>/samples on the VM
https://mcp.peacocks.me/rea/<project>/shared/   what its sessions share, read-only, /var/lib/rea/<project>/shared
```

A repo's `.mcp.json` points at its project (this one at `default`):

```json
{ "mcpServers": { "rea": { "type": "http", "url": "https://mcp.peacocks.me/rea/default/mcp" } } }
```

Adding a project is a line in `hosts/virtual/rea-dynamic` and a deploy, the edge needs nothing. Each session takes
about 1.5 times Ghidra's heap (`homelab.mcp.rea.ghidraHeap`, 1G here) once it has a target open, and all of them
together at most `homelab.mcp.rea.memoryMax` (75% of the VM): past that the kernel ends a session, not the VM.
There's no cap on sessions, so size the VM's `limits.memory` for what runs at once.

REA's tools take paths on the VM, so samples are uploaded first and opened by that path:

```sh
curl -T sample.apk https://mcp.peacocks.me/rea/default/samples/sample.apk
curl https://mcp.peacocks.me/rea/default/samples/                           # list
curl -X DELETE https://mcp.peacocks.me/rea/default/samples/sample.apk
```

From a cloud session the agent proxy adds the token. Uploads are up to 1G, one level (no subdirectories), land
`0644`, and the server only reads them.

### Projects and sharing

Projects keep work apart, they don't isolate it: everything runs as the `rea` user, and a sample one project
runs can reach every project's files. The VM is a disposable sandbox, what matters lives in the projects' repos.
Each project's sessions pass work along through its shared directory:

```
/var/lib/rea/<project>/
  samples/<name>                         uploads, read-only to REA
  shared/evidence/<branch>__<agent>.json export_evidence_bundle, import_evidence_bundle
  scratch/<agent>/<new dir>              extract_firmware output_directory, executable copies (REA's cwd)
  home/                                  REA's HOME
```

Agents on the same branch import each other's evidence, a different branch starts its own. REA only writes into
existing directories, so the names stay flat (`/` in a branch becomes `-`), and writes them `0600`, so
`rea-shared.path` makes them group-readable for nginx a moment after they land.

Bundles carry findings as evidence records, not a Ghidra database: importing one doesn't rename anything in the
importing session's binary, and REA's snapshots are the same records (no Ghidra analysis in them), so every
session pays Ghidra's analysis (~90 s for a 1 MB firmware) on its first query. Names and comments that should
outlive a session go in the project's repo (address, name, why) and are re-applied with `set_addresses_names` and
`annotate_native_function`; `set_comment` is Hopper only. Nothing in a session survives it ending (DELETE, 30 idle minutes, a reset) except what it exported, so agents
export after every finding worth keeping. To keep a bundle beyond the VM (in the project's repo, say), download
it, and upload it as a sample to import it again:

```sh
curl -fsS https://mcp.peacocks.me/rea/default/shared/evidence/                  # list
curl -fsSO https://mcp.peacocks.me/rea/default/shared/evidence/main__agent-1.json
curl -fsS -T main__agent-1.json https://mcp.peacocks.me/rea/default/samples/main__agent-1.json
```

### Dynamic analysis

`homelab.mcp.rea.dynamic = true` builds REA in full: `capture_process_scenario` runs the command it's given
under a PTY, `capture_browser_scenario` drives Chromium (`executable_path` `/etc/rea/chromium`, Playwright's own
build). Both work under the unit's sandbox as it is, nothing is relaxed. Samples run as `rea` and see what it
sees: the store, world-readable `/etc` and `/var/lib/rea`. Uploads aren't executable, copy one into scratch first
(`capture_process_scenario` with `install -m755 /var/lib/rea/<project>/samples/<name>
/var/lib/rea/<project>/scratch/<agent>/<name>`). rizin (`execute_rizin_command`, ESIL
emulation, debug sessions) and objdump are there; gdb, Frida and adb aren't on PATH, so their tools still fail, and binaries built for other distributions need their own
loader (no nix-ld), Electron apps included. `homelab.mcp.rea.firmware = true` adds binwalk and unblob (26.6, the
release REA takes) so `inspect_firmware_regions` and `extract_firmware` work; they parse untrusted blobs with
their own extractors, which is why they stay on this VM.

The VM serves nothing else (asserted), holds no secrets (it isn't a sops recipient) and is contained:

- **Who connects**: the router, `labs: edge to rea-dynamic` (and `labs: agents to rea-dynamic` per LAN agent).

- **Egress**: the router's `labs: rea-dynamic opens nothing` drops every connection the VM opens, so samples
  can't phone home or scan labs, and browser scenarios only load `http://127.0.0.1` pages. Nothing on the VM
  enforces it, so root there changes nothing. It has no DNS or NTP either, and deploys push the closure (no
  `--use-substitutes`).

- **Data**: `/var/lib/rea` is the `rea-data` volume, which the instance snapshot doesn't include. REA and nginx
  won't start without it. Create it once:

  ```sh
  incus storage volume create ceph rea-data --type=block size=100GiB
  incus config device add rea-dynamic data disk pool=ceph source=rea-data
  ssh admin@rea-dynamic lsblk                                   # the new, empty disk, e.g. sdb
  ssh admin@rea-dynamic 'sudo mkfs.ext4 -L rea-data /dev/sdb'
  ```

- **Reset**: snapshot the VM stopped once installed (and again after each deploy), roll its root back when no
  session is running. It restarts every session, the volume (and whatever samples wrote to it) stays:

  ```sh
  incus stop rea-dynamic && incus snapshot create rea-dynamic clean --reuse && incus start rea-dynamic
  incus snapshot restore rea-dynamic clean
  ```

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
