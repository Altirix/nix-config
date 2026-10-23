{ config, lib, ... }:

# The mcp VM's low-risk MCP servers at https://mcp.peacocks.me/<server>/mcp (streamable HTTP, no SSE), one
# bearer token per client. playwright (runs code), github and incus (hold credentials) get no route, and the VM
# only lets this host's tunnel address in on the routed ports. Never add a wireguard forward to 10.100.1.11:
# forwards arrive from that same address and would skip the token.
let
  # Each reads mcp-token-<name> from secrets/edge.yaml, drop one here (and its secret) to revoke it.
  clients = [ "laptop" "cloud" ];

  # Keep in step with the servers that let the edge in (`clients = edge` in hosts/virtual/mcp).
  servers = {
    rea = 8101;
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
    locations = lib.mapAttrs' (name: port: lib.nameValuePair "/${name}/mcp" "http://10.100.1.11:${toString port}/mcp") servers;
    tokens = config.sops.templates."mcp-tokens".path;
  };

  sops.secrets = lib.genAttrs (map secret clients) (key: {
    sopsFile = config.homelab.secrets.groupFile;
    inherit key;
  });

  sops.templates."mcp-tokens" = {
    content = lib.concatMapStrings (client: ''
      "Bearer ${config.sops.placeholder.${secret client}}" ${client};
    '') clients;
    owner = "nginx";
    reloadUnits = [ "nginx.service" ];
  };
}
