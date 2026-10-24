{ config, lib, ... }:

# The mcp VM's low-risk MCP servers at https://mcp.peacocks.me/<server>/mcp (streamable HTTP, no SSE), one
# bearer token per client. playwright (runs code), github and incus (hold credentials) get no route, and the VM
# only lets this host's tunnel address in on the routed ports. Never add a wireguard forward to 10.100.1.11:
# forwards arrive from that same address and would skip the token.
#
# REA is routed under /rea-dynamic/ to its own VM (10.100.1.12), whose nginx serves /<project>/mcp and
# /<project>/samples/, so projects come and go there alone. It runs code a caller hands it, but reaches nothing
# (no secrets, egress dropped in the VM and at the router, root reset from a snapshot), so a leaked token lands
# in a dead-end sandbox, not a pivot. That only holds while the router's egress drop is live and covers IPv6
# (modules/services/mcp/README.md). It uses the same token, so revoking it revokes the rest too.
let
  # Each reads mcp-token-<name> from this host's secrets.yaml, drop one here (and its secret) to revoke it.
  clients = [ "cloud" ];

  # Keep in step with the servers that let the edge in (`clients = edge` in hosts/virtual/mcp).
  servers = {
    nixos = 8102;
    context7 = 8104;
    fetch = 8105;
    time = 8106;
    memory = 8107;
    markitdown = 8109;
  };

  secret = client: "mcp-token-${client}";
in
{
  homelab.web.sites.mcp = {
    domains = [ "mcp.peacocks.me" ];
    https = true;
    locations = lib.mapAttrs' (name: port: lib.nameValuePair "/${name}/mcp" "http://10.100.1.11:${toString port}/mcp") servers
      # REA's nginx (homelab.mcp.rea.port), see hosts/virtual/rea-dynamic (its clients let only this host in).
      // { "/rea-dynamic/" = "http://10.100.1.12:8101/"; };
    # As REA's sample uploads.
    maxBodySize = "1g";
    tokens = config.sops.templates."mcp-tokens".path;
  };

  # From the host's secrets.yaml (sops.defaultSopsFile), only this host can read them.
  sops.secrets = lib.genAttrs (map secret clients) (key: { inherit key; });

  sops.templates."mcp-tokens" = {
    content = lib.concatMapStrings (client: ''
      "Bearer ${config.sops.placeholder.${secret client}}" ${client};
    '') clients;
    owner = "nginx";
    reloadUnits = [ "nginx.service" ];
  };
}
