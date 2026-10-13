{ config, lib, pkgs, ... }:

let
  host = config.networking.hostName;

  # Pool names differ per host (mirror vs raid10), so read them from disko.
  zpool = prefix: lib.findSingle (lib.hasPrefix prefix)
    (throw "incus: no ${prefix}* zpool in disko")
    (throw "incus: more than one ${prefix}* zpool in disko")
    (lib.attrNames config.disko.devices.zpool);
in
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

      # Incus creates the <pool>/incus datasets and the rbd pool itself on first preseed.
      storage_pools = [
        {
          name = "nvme";
          driver = "zfs";
          config = {
            source = "${zpool "nvme-"}/incus";
            "volume.zfs.blocksize" = "16KiB";
          };
        }
        {
          name = "bulk";
          driver = "zfs";
          config = {
            source = "${zpool "usb-"}/incus";
            "volume.zfs.blocksize" = "1MiB"; # capped to 128KiB for block volumes
          };
        }
        # Hosts aren't clustered, so each gets its own rbd pool, a shared one is refused as in use.
        {
          name = "ceph";
          driver = "ceph";
          config = {
            "ceph.cluster_name" = "ceph";
            "ceph.user.name" = "admin";
            "ceph.osd.pool_name" = "incus-${host}";
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
          devices.root = {
            path = "/";
            pool = "nvme";
            type = "disk";
          };
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

  # The ceph pool can't be created until the mons have quorum, retry without blocking switch.
  systemd.services.incus-preseed = {
    startLimitIntervalSec = 0;
    serviceConfig = {
      Type = lib.mkForce "simple";
      Restart = "on-failure";
      RestartSec = 15;
    };
  };

  # Incus maps rbd volumes through the kernel client.
  boot.kernelModules = [ "rbd" ];

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
