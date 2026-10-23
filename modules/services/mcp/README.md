# MCP

`homelab.mcp.servers` runs MCP servers for agents, each as its own `mcp-<name>` unit and port. stdio servers
sit behind mcp-proxy: streamable HTTP on `http://<host>:<port>/mcp`, SSE on `/sse`. Nothing authenticates, so
they stay off the edge and `homelab.mcp.clients` narrows them to the machines agents run on. stdio servers
share one process, and with it any state, between clients. `hosts/virtual/mcp` (`10.100.1.11`) serves them
on labs.

Presets in `servers/` only need enabling in the host, anything else is added directly:

```nix
homelab.mcp.servers.time = {
  enable = true;
  command = lib.getExe pkgs.mcp-server-time;
  port = 8100;
};
```

Add it to a client:

```sh
claude mcp add --transport http time http://<host>:8100/mcp
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
