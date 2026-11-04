# This host's sites: static ones from the old box (copy /var/www/<site>/public over after install), and the lab's
# services it puts on the internet. Each of those names the hosts that serve it (`from`, their homelab.publish) and
# who gets in, the way a forward names its peer. The router lets this host's tunnel address in on exactly their ports
# (each service's README), point every domain's A record here before the first deploy (ACME).
{
  # auth.peacocks.me, and sign-in for the `sso` sites below (modules/services/sso). Needs kanidm-web-secret and
  # oauth2-proxy-cookie-secret in secrets.yaml.
  homelab.sso.gateway = {
    enable = true;
    server = "auth";
  };

  homelab.web.sites = {
    blog = {
      root = "/var/www/blog/public";
      # upstream = "http://10.100.0.20";   # once the blog runs in the lab
      # domains = [ "example.com" "www.example.com" ];
      # https = true;
      default = true;
    };
    # Only reachable through the tunnel.
    blog-staging = {
      root = "/var/www/blog-staging/public";
      address = "10.0.0.1";
    };

    # The mcp VM's public MCP servers at /<server>/mcp and REA under /rea/ (modules/services/mcp/README.md). One
    # bearer token per client, mcp-token-<client> in secrets.yaml. Never add a wireguard forward to either VM:
    # forwards arrive from this host's tunnel address too and would skip the token.
    mcp = {
      domains = [ "mcp.peacocks.me" ];
      https = true;
      from = [ "mcp" "rea-dynamic" ];
      tokens = [ "cloud" ];
    };

    # The logs VM's UI and queries (modules/services/logs).
    logs = {
      domains = [ "logs.peacocks.me" ];
      https = true;
      from = [ "logs" ];
      sso = true;
    };

    # Part-DB (modules/services/partdb), then its own login.
    partdb = {
      domains = [ "parts.peacocks.me" ];
      https = true;
      from = [ "partdb" ];
      sso = true;
    };
  };
}
