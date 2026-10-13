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

  # Hosts never talk to or route for labs, VMs only reach the switch.
  networking.nftables.tables.labs-isolation = {
    family = "inet";
    content = let
      ifs = ''{ "labs", "${config.lan.labsUplink}" }'';
    in ''
      chain input {
        type filter hook input priority filter - 10; policy accept;
        iifname ${ifs} drop
      }
      chain forward {
        type filter hook forward priority filter - 10; policy accept;
        iifname ${ifs} drop
        oifname ${ifs} drop
      }
    '';
  };

  networking.firewall.interfaces = lib.genAttrs config.lan.adminInterfaces (_: {
    allowedTCPPorts = [ 8443 ];
  });
  users.users.admin.extraGroups = [ "incus-admin" ];
}
