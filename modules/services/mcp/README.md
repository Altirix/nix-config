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
