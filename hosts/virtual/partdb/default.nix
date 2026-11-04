{ ... }:

# Part-DB, electronic parts inventory. Only on labs until SSO is in front of it, no homelab.web site yet.
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

  # Only on the labs bridge.
  networking.firewall.allowedTCPPorts = [ 80 ];
}
