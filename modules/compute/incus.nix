{ config, lib, pkgs, ... }:

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

      networks = [
        {
          name = "labs";
          type = "bridge";
          config = {
            "bridge.external_interfaces" = config.lan.labsUplink;
            "ipv4.address" = "none";
            "ipv6.address" = "none";
          };
        }
      ];

      # Instances can only attach to labs.
      projects = [
        {
          name = "default";
          config = {
            "restricted" = "true";
            "restricted.devices.nic" = "managed";
            "restricted.backups" = "allow";
            "restricted.snapshots" = "allow";
            "restricted.cluster.target" = "allow";
          };
        }
      ];

      profiles = [
        {
          name = "default";
          devices.eth0 = {
            name = "eth0";
            network = "labs";
            type = "nic";
          };
        }
      ];
    };
  };

  networking.firewall.interfaces = lib.genAttrs config.lan.adminInterfaces (_: {
    allowedTCPPorts = [ 8443 ];
  });
  users.users.admin.extraGroups = [ "incus-admin" ];
}
