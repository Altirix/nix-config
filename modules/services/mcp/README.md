# MCP

`homelab.mcp.servers` runs MCP servers for agents, each as its own `mcp-<name>` unit and port. stdio servers
sit behind mcp-proxy: streamable HTTP on `http://<host>:<port>/mcp`, SSE on `/sse`. Nothing authenticates, so
the router decides who reaches which port (Router), and only the edge's nginx (with OAuth) puts the low-risk
ones on the internet (From outside). The VMs open every port they serve: a firewall on a VM is gone with root
on it, so none of what keeps them apart lives there. stdio servers share one process, and with it any state,
between clients. `hosts/virtual/mcp` (`10.100.1.11`) serves them on labs.

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
request needs an OAuth access token from Kanidm (`hosts/virtual/auth`, [README](../../../hosts/virtual/auth/README.md)),
which only signs in members of `mcp_users`. The router only lets the edge's tunnel
address `10.0.0.1` in on the exposed servers' ports (`labs: edge to mcp`, Router), so a compromised edge still
doesn't reach the others. Never add a wireguard forward to `10.100.1.11` or `10.100.1.12`: forwards arrive from
`10.0.0.1` too and would skip the check. Exposing another server takes both, `servers` in `mcp.nix` and its port
in `labs: edge to mcp`.

How a client gets in (the MCP authorization spec): its first request gets a 401 whose `WWW-Authenticate` points at
`/.well-known/oauth-protected-resource/<server>/mcp` (RFC 9728, one per location, written by
`modules/services/web`), which names the issuer `https://auth.peacocks.me/oauth2/openid/mcp`. The client signs the
person in there (authorization code + PKCE) and sends `Authorization: Bearer <access token>` from then on, refreshing
it every 15 minutes. On the edge, nginx asks oauth2-proxy (loopback, `auth_request`) about each request; it checks the
token's ES256 signature against Kanidm's keys, its issuer, audience (`mcp` or `mcp-cli`) and expiry, offline.
Cookies don't count, the upstream never sees the token, and the access log names the person (the token's `sub`,
their Kanidm uuid: `kanidm person get <uuid>`). Kanidm has no dynamic client registration, so clients are given
their client id.

REA is also routed, `https://mcp.peacocks.me/rea/` → its own VM's nginx `10.100.1.12:8101`, behind the same
sign-in. It runs code a caller hands it but reaches nothing (no secrets, the router drops what it opens,
snapshot reset), so a leaked token lands in a dead-end sandbox. That rests on `labs: rea-dynamic opens nothing`
(Router) being live, and covering IPv6 too if labs carries it.

Set it up: Kanidm first ([its README](../../../hosts/virtual/auth/README.md#set-up)), point an A record for
`mcp.peacocks.me` at the VPS (ACME needs it before the first deploy), add the router rules (Router), deploy `mcp`,
then `ionos-de`. ionos-de doesn't build without `kanidm-mcp-secret` and `oauth2-proxy-cookie-secret` in its
`secrets.yaml`. Revoke a person by removing them from `mcp_users` (or Kanidm) and destroying their sessions: their
access token lasts at most 15 more minutes, no refresh after that.

Check from anywhere, without a token (401, and the metadata it points at):

```sh
curl -i https://mcp.peacocks.me/time/mcp -d '{}'
curl https://mcp.peacocks.me/.well-known/oauth-protected-resource/time/mcp
```

Claude (claude.ai, desktop and mobile apps): Settings → Connectors → Add custom connector, URL
`https://mcp.peacocks.me/<server>/mcp`, and under Advanced settings the OAuth client id `mcp` and its secret
(`kanidm system oauth2 show-basic-secret mcp`). Connecting opens Kanidm's sign-in.

Claude Code, per server, signs in with `/mcp` in a session (browser on this machine, callback on the port given):

```sh
claude mcp add --transport http --client-id mcp-cli --callback-port 8976 time https://mcp.peacocks.me/time/mcp
```

Or in a repo's `.mcp.json`, as this repo's own:

```json
{
  "mcpServers": {
    "time": {
      "type": "http",
      "url": "https://mcp.peacocks.me/time/mcp",
      "oauth": { "clientId": "mcp-cli", "callbackPort": 8976 }
    }
  }
}
```

Scripts and headless agents (curl, Claude Code cloud sessions) can't do a browser sign-in. A Kanidm service account
in `mcp_users` can: its API token is exchanged for a 15 minute access token (RFC 8693, no client secret), which works
anywhere a person's does. It isn't set up; a cloud session would need the API token itself (an environment variable)
and to exchange it before each use:

```sh
kanidm service-account create <name> "<display name>" idm_admins -H https://auth.peacocks.me -D idm_admin
kanidm group add-members mcp_users <name> -H https://auth.peacocks.me -D idm_admin
kanidm service-account api-token generate <name> <label> -H https://auth.peacocks.me -D idm_admin
curl -s https://auth.peacocks.me/oauth2/token -d client_id=mcp-cli -d scope=openid \
  -d grant_type=urn:ietf:params:oauth:grant-type:token-exchange \
  -d subject_token_type=urn:ietf:params:oauth:token-type:access_token \
  --data-urlencode subject_token="$KANIDM_API_TOKEN" | jq -r .access_token
```

## Usage

Two views, both in VictoriaLogs (`hosts/virtual/logs`):

- **Every client, per request**: the edge's access log (`SYSLOG_IDENTIFIER:nginx_access`) has the user, path,
  status and duration of each request through `mcp.peacocks.me`. It can't see inside them (which tool, with what).
- **Claude Code, per tool call**: Claude Code's own OpenTelemetry export has a `claude_code.tool_result` event for
  every tool it calls, MCP or not, with the tool, its MCP server, success, error and duration, and with
  `OTEL_LOG_TOOL_DETAILS=1` its parameters (which can hold secrets). VictoriaLogs takes OTLP directly. In
  `~/.claude/settings.json` on each machine that should report (one that reaches the logs VM, `labs: logs in`), not
  this repo's `.claude/settings.json`, which cloud sessions also read and couldn't send from:

  ```json
  {
    "env": {
      "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
      "OTEL_LOGS_EXPORTER": "otlp",
      "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
      "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT": "http://10.100.0.11:9428/insert/opentelemetry/v1/logs",
      "OTEL_LOG_TOOL_DETAILS": "1"
    }
  }
  ```

  ```
  claude_code.tool_result mcp_server_name:* | stats by (mcp_server_name, mcp_tool_name, success) count()
  claude_code.tool_result success:false | fields _time, mcp_tool_name, error, tool_parameters
  ```

Claude's connectors (claude.ai, the apps) only show up in the access log, they export nothing.

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

Each needs `-H "Authorization: Bearer <access token>"` (From outside). Uploads are up to 1G, one level (no subdirectories), land
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
