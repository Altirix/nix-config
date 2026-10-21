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
  };

  # Only on the labs bridge.
  networking.firewall.allowedTCPPorts = [ 80 ];
}
