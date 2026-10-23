# MCP

`homelab.mcp.servers` runs MCP servers for agents, each as its own `mcp-<name>` unit and port. stdio servers
sit behind mcp-proxy: streamable HTTP on `http://<host>:<port>/mcp`, SSE on `/sse`. Nothing authenticates, so
they stay off the edge and `homelab.mcp.clients` narrows them to the machines agents run on. stdio servers
share one process, and with it any state, between clients. `hosts/virtual/mcp` (`10.100.1.11`) serves them
on labs.

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

## rea (8101)

Decompiles with Ghidra and reads APKs with JADX, static analysis only, one open target at a time. Copy targets
to `/var/lib/rea-samples` on `mcp` (rsync as admin) and open them by that path.

### Dynamic analysis (rea-dynamic)

`homelab.mcp.rea.dynamic = true` builds REA in full: `capture_process_scenario` runs the command it's given
under a PTY, `capture_browser_scenario` drives Chromium (`executable_path` `/etc/rea/chromium`, Playwright's own
build). Both work under the unit's sandbox as it is, nothing is relaxed. Samples run as the unit's dynamic user
and see what it sees: the store, world-readable `/etc`, its state directory and `/var/lib/rea-samples`. gdb,
rizin, Frida and adb aren't on PATH, so their tools still fail, and binaries built for other distributions need
their own loader (no nix-ld), Electron apps included.

That only runs on `hosts/virtual/rea-dynamic` (`10.100.1.12`, samples go to its `/var/lib/rea-samples`), which
serves nothing else (asserted), holds no secrets and is contained:

- **Who connects**: a router rule and `homelab.mcp.clients` as for `mcp`, for 8101 on `10.100.1.12`. It goes
  before `labs: only home and tunnel in`, which drops everything else home opens into labs:

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

- **Reset**: snapshot the VM stopped once installed (and again after each deploy), roll back after every
  analysis:

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
