{ config, lib, ... }:

# Part-DB, electronic parts inventory, published (homelab.publish) for a front door with sign-in (parts.peacocks.me),
# then Part-DB's own login. Logged out, Part-DB acts as its built-in `anonymous` user (disabling that user changes
# nothing in 2.4), so nothing is visible logged out only once that user's permissions are taken away: a one-time
# step in its UI, it keeps them in its database. As an admin, open the users admin, edit `anonymous`, take it out
# of every group and set every permission to Forbid; then check from a private window that the site only offers the
# login. The router lets only the edge in, from home use the site too:
#
#   /ip firewall filter
#   add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=<host> protocol=tcp dst-port=80 comment="labs: edge to partdb" place-before=[find comment="labs: only home and tunnel in"]
let
  cfg = config.homelab.partdb;
in
{
  imports = [ ../web/publish.nix ];

  options.homelab.partdb = {
    enable = lib.mkEnableOption "Part-DB";
    # Where it's reached, for links in emails and URLs built without a request.
    url = lib.mkOption { type = lib.types.str; };
    # The front door's address: its X-Forwarded-* say https and the client's address (session cookies are Secure).
    trustedProxies = lib.mkOption { type = lib.types.listOf lib.types.str; };
  };

  config = lib.mkIf cfg.enable {
    services.part-db = {
      enable = true;
      enableNginx = true;
      enablePostgresql = true;
      virtualHost = "partdb";
      settings = {
        DEFAULT_URI = cfg.url;
        TRUSTED_PROXIES = lib.concatStringsSep "," cfg.trustedProxies;
      };
      # A worker stuck on a lock is killed instead of holding the pool forever.
      poolConfig."request_terminate_timeout" = "60s";
    };

    # The module sets APP_SHARE_DIR here but never creates it, the parent is root owned (tmpfiles makes it for
    # env.local). Without it the Symfony cache never saves and workers deadlock on its stampede flocks.
    # Fixed upstream in nixpkgs b7dcd54f64 (master, not in 26.05), drop on 26.11.
    systemd.tmpfiles.settings."10-part-db"."/var/lib/part-db/share".d = {
      user = "part-db";
      group = "part-db";
      mode = "0750";
    };

    homelab.publish.upstream = "http://${config.homelab.labs.address}";

    # Only on the labs bridge.
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
