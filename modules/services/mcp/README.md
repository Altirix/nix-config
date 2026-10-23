# MCP

`homelab.mcp.servers` runs MCP servers for agents, each as its own `mcp-<name>` unit and port. stdio servers
sit behind mcp-proxy: streamable HTTP on `http://<host>:<port>/mcp`, SSE on `/sse`. Nothing authenticates, so
they stay off the edge. stdio servers share one process, and with it any state, between clients.
`hosts/virtual/mcp` (`10.100.1.11`) serves them on labs.

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
