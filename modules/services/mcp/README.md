# MCP

`homelab.mcp.servers` runs MCP servers for agents, each as its own `mcp-<name>` unit and port. stdio servers
sit behind mcp-proxy: streamable HTTP on `http://<host>:<port>/mcp`, SSE on `/sse`. Nothing authenticates, so
they stay off the edge. stdio servers share one process, and with it any state, between clients.

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
