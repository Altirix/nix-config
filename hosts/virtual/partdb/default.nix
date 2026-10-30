{ ... }:

# Part-DB, electronic parts inventory, at https://parts.peacocks.me behind Kanidm sign-in (hosts/edge/ionos-de/partdb.nix),
# then Part-DB's own login. Logged out, Part-DB acts as its built-in `anonymous` user (disabling that user changes
# nothing in 2.4), so nothing is visible logged out only once that user's permissions are taken away: a one-time
# step in its UI, it keeps them in its database. As an admin, open the users admin, edit `anonymous`, take it out
# of every group and set every permission to Forbid; then check from a private window that the site only offers the
# login. The router lets only the edge in, from home use the site too:
#
#   /ip firewall filter
#   add chain=forward action=accept connection-state=new in-interface=wg-vpn src-address=10.0.0.1 dst-address=10.100.2.10 protocol=tcp dst-port=80 comment="labs: edge to partdb" place-before=[find comment="labs: only home and tunnel in"]
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  services.part-db = {
    enable = true;
    enableNginx = true;
    enablePostgresql = true;
    virtualHost = "partdb";
    settings = {
      # Links in emails, and URLs built without a request.
      DEFAULT_URI = "https://parts.peacocks.me/";
      # The edge's tunnel address: its X-Forwarded-* say https and the client's address (session cookies are Secure).
      TRUSTED_PROXIES = "10.0.0.1";
    };
  };

  # Only on the labs bridge.
  networking.firewall.allowedTCPPorts = [ 80 ];
}
