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
        {
          name = "labs-mesh";
          type = "bridge";
          config = {
            "bridge.external_interfaces" = config.mesh.labsMeshUplink;
            "bridge.mtu" = toString config.mesh.labsMeshMtu;
            "ipv4.address" = "none";
            "ipv6.address" = "none";
          };
        }
      ];

      # Instances can only attach to labs and labs-mesh.
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
        # Opt in with `-p default -p labs-mesh` for VM to VM traffic over the mesh.
        {
          name = "labs-mesh";
          devices.eth1 = {
            name = "eth1";
            network = "labs-mesh";
            type = "nic";
          };
        }
      ];
    };
  };

  # Hosts never talk to or route for instance networks, so instances can't reach mgmt or ceph.
  networking.nftables.tables.instance-isolation = {
    family = "inet";
    content = let
      ifs = ''{ "labs", "${config.lan.labsUplink}", "labs-mesh", "${config.mesh.labsMeshUplink}" }'';
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
