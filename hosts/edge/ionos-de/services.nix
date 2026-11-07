# This host's sites: static ones from the old box (copy /var/www/<site>/public over after install), and the lab's
# services it fronts (`from`). Each service's README has its secrets and router rules, every domain's A record points
# here before the first deploy (ACME).
{
  # auth.peacocks.me, and sign-in for the `sso` sites (modules/services/sso).
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

    # MCP servers and REA, a bearer token per client (modules/services/mcp/README.md). No wireguard forward to either.
    # Every call is audited.
    mcp = {
      domains = [ "mcp.peacocks.me" ];
      https = true;
      from = [ "mcp" "rea-dynamic" ];
      tokens = [ "cloud" ];
      audit = true;
    };

    # modules/services/logs
    logs = {
      domains = [ "logs.peacocks.me" ];
      https = true;
      from = [ "logs" ];
      sso.title = "Logs";
    };

    # modules/services/inventree, next to Part-DB to compare.
    inventree = {
      domains = [ "inventree.peacocks.me" ];
      https = true;
      from = [ "inventree" ];
      sso.title = "InvenTree";
    };

    # modules/services/paperless
    paperless = {
      domains = [ "docs.peacocks.me" ];
      https = true;
      from = [ "paperless" ];
      sso.title = "Paperless";
    };

    # modules/services/partdb
    partdb = {
      domains = [ "parts.peacocks.me" ];
      https = true;
      from = [ "partdb" ];
      sso.title = "Part-DB";
    };
  };
}
