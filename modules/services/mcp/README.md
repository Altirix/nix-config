# MCP

`homelab.mcp.servers` runs MCP servers for agents, each as its own `mcp-<name>` unit and port. stdio servers
sit behind mcp-proxy: streamable HTTP on `http://<host>:<port>/mcp`, SSE on `/sse`. Nothing authenticates, so
`homelab.mcp.clients` narrows them to the machines agents run on, and only the edge's nginx (with tokens) puts
the low-risk ones on the internet (From outside). stdio servers share one process, and with it any state,
between clients, unless `sessions = "isolated"` gives each MCP session its own (mcp-session-proxy, `/mcp` only,
`maxSessions` at once, closed after 30 idle minutes). `hosts/virtual/mcp` (`10.100.1.11`) serves them on labs.

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

## Reaching them

The router only lets home in on ssh and RDP, and nothing else into labs, VMs included. Let the machines agents
run on reach the MCP ports:

```routeros
/ip firewall filter
add chain=forward action=accept connection-state=new src-address=<agent> dst-address=10.100.1.11 protocol=tcp dst-port=8100-8199 comment="labs: agents to mcp" place-before=[find comment="labs: only home and tunnel in"]
```

Then list the same machines in `homelab.mcp.clients` on the host, so the VM's own nftables drops everyone else
too and one mistake doesn't open both:

```nix
homelab.mcp.clients = [ "10.10.0.20" ];
```

Unset lets in anyone who gets past the router, `[ ]` no one. A server can narrow it further (or widen it to
one more machine) with its own `clients`, which defaults to that list:

```nix
homelab.mcp.servers.time.clients = config.homelab.mcp.clients ++ [ "10.0.0.1" ];
```

## From outside

`hosts/edge/ionos-de/mcp.nix` serves nixos, context7, fetch, time, memory and markitdown at
`https://mcp.peacocks.me/<server>/mcp`, proxied over the tunnel (streamable
HTTP only, SSE is deprecated). playwright runs code, github and incus hold credentials, they get no route. Every
request needs `Authorization: Bearer <token>`, one token per client in `hosts/edge/ionos-de/secrets.yaml` so each
can be revoked, and the access log names the client. The router already lets the tunnel into labs, and the VM sees the edge as its
tunnel address `10.0.0.1`, which `hosts/virtual/mcp` lets in on the exposed servers' ports only, so a
compromised edge still doesn't reach the others. If the router ever masquerades into labs it becomes
`10.100.0.1` instead, check with `journalctl -k` on `mcp` (dropped connections are logged) if the edge gets
502s. Never add a wireguard forward to `10.100.1.11`: forwards arrive from `10.0.0.1` too and would skip the
token. Exposing another server takes both, `servers` in `mcp.nix` and `clients = edge` in `hosts/virtual/mcp`.

REA is also routed, `https://mcp.peacocks.me/rea-dynamic/` → its own VM's nginx `10.100.1.12:8101`, on the same
token. It runs code a caller hands it but reaches nothing (no secrets, egress dropped, snapshot reset),
so a leaked token lands in a dead-end sandbox. That rests on the egress drop holding even against root in the
VM, so the router's "rea-dynamic opens nothing" drop (below, the real backstop, the VM can flush its own) must
be live, and must cover IPv6 too if labs carries it, or VM-root egresses over v6:

```routeros
/ipv6 firewall filter
add chain=forward action=drop connection-state=new src-address=<rea-dynamic v6> comment="labs: rea-dynamic opens nothing (v6)" place-before=[find comment="labs: no connection to private wg ips"]
```

Set it up: point an A record for `mcp.peacocks.me` at the VPS (ACME needs it before the first deploy), add a
token per client named in `mcp.nix` (`openssl rand -hex 32`), uncomment `./mcp.nix` in
`hosts/edge/ionos-de/default.nix`, deploy `mcp`, then `ionos-de`. ionos-de doesn't build with it uncommented and
the tokens missing.

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

Or in a repo's `.mcp.json`, reading the token from the environment when Claude Code starts. Don't commit one to
this repo, every session would try to connect:

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

## rea (rea-dynamic, 8101)

Decompiles with Ghidra, reads APKs with JADX, runs samples and unpacks firmware. It only runs on
`hosts/virtual/rea-dynamic` (`10.100.1.12`), one server per project in `homelab.mcp.rea.projects`, and every MCP
session gets its own REA process with its own open target, so agents never close or replace each other's.
nginx on 8101 (`homelab.mcp.rea.port`, opened to `homelab.mcp.rea.clients`) is the only way in, the project
servers (`mcp-rea-<project>`, 8120 onwards) only listen for it:

```
https://mcp.peacocks.me/rea-dynamic/<project>/mcp        the project's server
https://mcp.peacocks.me/rea-dynamic/<project>/samples/   its uploads, /var/lib/rea-samples/<project> on the VM
```

A repo's `.mcp.json` points at its project (this one at `default`):

```json
{ "mcpServers": { "rea-dynamic": { "type": "http", "url": "https://mcp.peacocks.me/rea-dynamic/default/mcp" } } }
```

Adding a project is a line in `hosts/virtual/rea-dynamic` and a deploy, the edge needs nothing. Each session takes
up to 2G (Ghidra's heap), at most 4 per project (`homelab.mcp.servers.rea-<project>.maxSessions`), so size the
VM's `limits.memory` for what runs at once.

REA's tools take paths on the VM, so samples are uploaded first and opened by that path:

```sh
curl -T sample.apk https://mcp.peacocks.me/rea-dynamic/default/samples/sample.apk
curl https://mcp.peacocks.me/rea-dynamic/default/samples/                          # list
curl -X DELETE https://mcp.peacocks.me/rea-dynamic/default/samples/sample.apk
```

From a cloud session the agent proxy adds the token. Uploads are up to 1G, one level (no subdirectories), land
`0644`, and the server only reads them.

### Projects and sharing

Each project is its own dynamic user and sees only its own samples (read-only) and state directory
`/var/lib/mcp-rea-<project>`, which all of its sessions share; another project's are out of reach, samples run
there included. Sessions pass work along through the state directory:

```
/var/lib/mcp-rea-<project>/
  shared/snapshots/<sha256>.snap          close_binary snapshot_path (overwrite: false), open_binary snapshot_path
  shared/<branch>/evidence/<agent>.json   export_evidence_bundle, import_evidence_bundle
  scratch/<agent>/<new dir>               extract_firmware output_directory, executable copies
```

Agents on the same branch import each other's evidence, a different branch starts its own. A snapshot skips
Ghidra's analysis for the next session on the same sample, but can only be saved before any rename or comment.

### Dynamic analysis

`homelab.mcp.rea.dynamic = true` builds REA in full: `capture_process_scenario` runs the command it's given
under a PTY, `capture_browser_scenario` drives Chromium (`executable_path` `/etc/rea/chromium`, Playwright's own
build). Both work under the unit's sandbox as it is, nothing is relaxed. Samples run as the project's dynamic
user and see what it sees: the store, world-readable `/etc`, its state directory and its samples. Uploads aren't
executable, copy one into scratch first (`capture_process_scenario` with `install -m755
/var/lib/rea-samples/<project>/<name> /var/lib/mcp-rea-<project>/scratch/<agent>/<name>`). gdb, rizin, Frida
and adb aren't on PATH, so their tools still fail, and binaries built for other distributions need their own
loader (no nix-ld), Electron apps included. `homelab.mcp.rea.firmware = true` adds binwalk and unblob (26.6, the
release REA takes) so `inspect_firmware_regions` and `extract_firmware` work; they parse untrusted blobs with
their own extractors, which is why they stay on this VM.

The VM serves nothing else (asserted), holds no secrets and is contained:

- **Who connects**: a router rule and `homelab.mcp.rea.clients`, for 8101 on `10.100.1.12`. It goes before
  `labs: only home and tunnel in`, which drops everything else home opens into labs:

  ```routeros
  /ip firewall filter
  add chain=forward action=accept connection-state=new src-address=<agent> dst-address=10.100.1.12 protocol=tcp dst-port=8101 comment="labs: agents to rea-dynamic" place-before=[find comment="labs: only home and tunnel in"]
  ```

- **Egress**: the VM's nftables drops every packet it would send that isn't loopback, IPv6 neighbour
  discovery or part of a connection made to it, so samples can't phone home or scan labs, and browser
  scenarios only load `http://127.0.0.1` pages. It has no DNS or NTP either, and deploys push the closure (no
  `--use-substitutes`). The router drops what the VM opens as well, in case root in the VM is lost:

  ```routeros
  /ip firewall filter
  add chain=input action=drop connection-state=new src-address=10.100.1.12 comment="labs: rea-dynamic opens nothing" place-before=0
  add chain=forward action=drop connection-state=new src-address=10.100.1.12 comment="labs: rea-dynamic opens nothing" place-before=[find comment="labs: no connection to private wg ips"]
  ```

- **Data**: samples and the projects' state live on the `rea-data` volume (`/srv/rea`, bind-mounted on
  `/var/lib/rea-samples` and `/var/lib/private`), which the instance snapshot doesn't include. REA and nginx
  won't start without it. Create it once:

  ```sh
  incus storage volume create ceph rea-data --type=block size=100GiB
  incus config device add rea-dynamic data disk pool=ceph source=rea-data
  ssh admin@rea-dynamic 'sudo mkfs.ext4 -L rea-data /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_incus_data'
  ssh admin@rea-dynamic 'sudo mount /dev/disk/by-label/rea-data /mnt && sudo install -d -m700 /mnt/private && sudo install -d -m755 /mnt/samples && sudo umount /mnt'
  ```

- **Reset**: snapshot the VM stopped once installed (and again after each deploy), roll its root back when no
  session is running. It restarts every session, the volume (and what samples wrote into their project) stays:

  ```sh
  incus stop rea-dynamic && incus snapshot create rea-dynamic clean --reuse && incus start rea-dynamic
  incus snapshot restore rea-dynamic clean
  ```

## github (8103)

Read-only with one server-side token, so every client reads as its owner. Use a fine-grained PAT with read-only
Contents, Issues, Pull requests and Metadata on the repos it should see (a classic one needs `repo`, which also
allows writes). Add the mcp VM's age key to the `virtual` group in `.sops.yaml` (see Secrets in the top
README), add the token, then uncomment the enable line in `hosts/virtual/mcp`. The host doesn't build with it
enabled and no token.

```sh
sops updatekeys secrets/virtual.yaml
sops secrets/virtual.yaml   # github-mcp-token: github_pat_...
```

## context7 (8104)

Serves its own `/mcp` (no `/sse`). An API key is optional, per client: `--header "Context7-API-Key: <key>"`.

## incus (8110)

Reads the incus cluster with a restricted client certificate. Incus routes restricted certificates to
`modules/compute/incus-restricted.star`, which lets them view the `default` project, storage pools, members and
resources, and change nothing: no exec, console, files, state changes, operations or events. The key still
reads every instance's config and logs, and so does anyone who reaches 8110, narrow it with `clients`. The VM
reaches the API on the members' mgmt addresses, so the router has to let it (only its address) from labs to
mgmt on tcp/8443. Set it up with the cluster's certificate and a new key:

```sh
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:secp384r1 -nodes -days 3650 \
  -subj /CN=mcp-incus -keyout incus-mcp.key -out modules/compute/incus-mcp.crt
ssh admin@andromeda incus query /1.0 | jq -r .environment.certificate > modules/compute/incus-cluster.crt
```

Uncomment `restrictedCertificates.mcp-incus` in `modules/compute.nix` and deploy the hypervisors. That also
makes the scriptlet the policy for every restricted certificate, hand-added ones included (`incus config trust
list` shows which are). Dropping either from nix later leaves it in place, `incus config trust remove` and
`incus config unset` take it out. Add the mcp VM's age key to the `virtual` group in `.sops.yaml`, add the key
as `incus-mcp-key` (the PEM as a `|` block), delete `incus-mcp.key`, then uncomment the incus block in
`hosts/virtual/mcp`.

```sh
sops updatekeys secrets/virtual.yaml
sops secrets/virtual.yaml   # incus-mcp-key: |
```
