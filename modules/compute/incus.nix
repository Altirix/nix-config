{ config, pkgs, ... }:

{
  virtualisation.incus = {
    enable = true;
    ui.enable = true;
    package = pkgs.incus;
    preseed = {
      config."core.https_address" = ":8443";
      certificates = [
        {
          name = "my-browser";
          type = "client";
          certificate = builtins.readFile ./config/incus-ui.crt;
        }
      ];
      profiles = [
        {
          name = "default";
          devices.eth0 = {
            name = "eth0";
            nictype = "bridged";
            parent = "incus-br0";
            type = "nic";
          };
        }
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [ 8443 ]; 
  users.users.admin.extraGroups = [ "incus-admin" ];
}