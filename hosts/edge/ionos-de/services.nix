# This host's sites: static ones from the old box (copy /var/www/<site>/public over after install), and the lab's
# services it fronts (`from`). Each service's README has its secrets and router rules, every domain's A record points
# here before the first deploy (ACME).
{ nodes, ... }:

let
  mcpWeb = nodes.mcp-web.config;
  # A playwright's noVNC view on mcp-web (modules/services/mcp/servers/playwright.nix).
  view = browser: "http://${mcpWeb.homelab.labs.address}:${toString mcpWeb.homelab.mcp.playwright.${browser}.viewPort}/";
in
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
      from = [ "mcp" "mcp-web" "rea" ];
      tokens = [ "cloud" ];
      audit = true;
    };

    # The playwrights' displays (modules/services/mcp/README.md, Solving a challenge), signed in through Kanidm: they
    # drive the browsers with no password of their own. Named here rather than published by mcp-web, whose
    # publications are the token-checked MCP site's.
    browser = {
      domains = [ "browser.peacocks.me" ];
      https = true;
      sso.title = "Browsers";
      # A page linking to both views (browser/index.html), the views themselves only open signed in.
      root = "${./browser}";
      locations = {
        "/chromium/" = view "chromium";
        "/firefox/" = view "firefox";
      };
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

    # modules/services/home-assistant
    hass = {
      domains = [ "ha.peacocks.me" ];
      https = true;
      from = [ "hass" ];
      sso.title = "Home Assistant";
    };
  };
}
