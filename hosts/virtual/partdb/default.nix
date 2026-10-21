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
    # The version is pinned by nixpkgs, and the check hangs the home page when GitHub is unreachable.
    settings.CHECK_FOR_UPDATES = "0";
  };

  # Only on the labs bridge.
  networking.firewall.allowedTCPPorts = [ 80 ];
}
