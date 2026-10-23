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
