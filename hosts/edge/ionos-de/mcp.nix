{ lib, ... }:

# The mcp VM's low-risk MCP servers at https://mcp.peacocks.me/<server>/mcp (streamable HTTP, no SSE), behind
# OAuth: clients sign in to Kanidm (auth.nix, hosts/virtual/auth) and every request needs its access token, checked
# here by oauth2-proxy. Who may sign in is Kanidm's mcp_users group. playwright (runs code) and github (holds a token)
# get no route, and the router only lets this host's tunnel address in on the routed ports. Never add a wireguard
# forward to 10.100.1.11 or 10.100.1.12: forwards arrive from that same address and would skip the check.
#
# REA is routed under /rea/ to its own VM (hosts/virtual/rea-dynamic, 10.100.1.12), whose nginx serves
# /<project>/mcp, /<project>/samples/ and /<project>/shared/, so projects come and go there alone. It runs code a
# caller hands it, but reaches nothing (no secrets, the router drops all it opens, root reset from a snapshot), so a
# leaked token lands in a dead-end sandbox, not a pivot. That only holds while the router's drop is live and covers
# IPv6 (modules/services/mcp/README.md). The same sign-in covers it.
let
  # Keep in step with the router's "labs: edge to mcp" ports (modules/services/mcp/README.md).
  servers = {
    nixos = 8102;
    context7 = 8104;
    fetch = 8105;
    time = 8106;
    memory = 8107;
    markitdown = 8109;
  };

  # Kanidm's OAuth2 clients (hosts/virtual/auth): mcp for Claude's connectors, mcp-cli (public) for Claude Code.
  issuer = client: "https://auth.peacocks.me/oauth2/openid/${client}";
in
{
  homelab.web.sites.mcp = {
    domains = [ "mcp.peacocks.me" ];
    https = true;
    locations = lib.mapAttrs' (name: port: lib.nameValuePair "/${name}/mcp" "http://10.100.1.11:${toString port}/mcp") servers
      # REA's nginx (homelab.mcp.rea.port), see hosts/virtual/rea-dynamic.
      // { "/rea/" = "http://10.100.1.12:8101/"; };
    # As REA's sample uploads.
    maxBodySize = "1g";
    oauth = true;
  };

  # Clients are sent to the mcp client's issuer, tokens of either client count. oauth2-proxy itself (and its secrets)
  # is set up in auth.nix.
  homelab.web.oauth = {
    resourceIssuer = issuer "mcp";
    extraIssuers = {
      ${issuer "mcp"} = "mcp";
      ${issuer "mcp-cli"} = "mcp-cli";
    };
  };
}
