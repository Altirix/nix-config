{ config, lib, pkgs, nodes, ... }:

let
  mesh = config.mesh;
  host = config.networking.hostName;
  json = pkgs.formats.json { };

  # Pool names differ per host (mirror vs raid10), so read them from disko.
  zpool = prefix: lib.findSingle (lib.hasPrefix prefix)
    (throw "incus: no ${prefix}* zpool in disko")
    (throw "incus: more than one ${prefix}* zpool in disko")
    (lib.attrNames config.disko.devices.zpool);

  # Lowest nodeId creates the cluster, everyone else joins it.
  seed = lib.head (lib.sort (a: b: nodes.${a}.config.mesh.nodeId < nodes.${b}.config.mesh.nodeId)
    (lib.attrNames mesh.addresses));
  address = "${mesh.routerIp}:8443";

  # Trusted cluster-wide, re-adding one through preseed fails, so the bootstrap adds missing ones.
  certificates = {
    my-browser = ./config/incus-ui.crt;
    incus-join = ./config/incus-join.crt; # lets a new member fetch its own join token
  };

  # `member` keys are per host, they're set on create and through member_config on join,
  # never in the cluster-wide preseed.
  networks = [
    {
      name = "labs";
      type = "bridge";
      config = {
        "ipv4.address" = "none";
        "ipv6.address" = "none";
      };
      member."bridge.external_interfaces" = config.lan.labsUplink;
    }
    {
      name = "labs-mesh";
      type = "bridge";
      config = {
        "bridge.mtu" = toString mesh.labsMeshMtu;
        "ipv4.address" = "none";
        "ipv6.address" = "none";
      };
      member."bridge.external_interfaces" = mesh.labsMeshUplink;
    }
  ];

  # Incus takes over the disko vm/bulk datasets (must have no child datasets), children inherit their recordsize.
  # volblocksize does not inherit, so zvols still need volume.zfs.blocksize.
  storagePools = [
    {
      name = "nvme";
      driver = "zfs";
      config."volume.zfs.blocksize" = "16KiB";
      member.source = "${zpool "nvme-"}/vm";
    }
    {
      name = "bulk";
      driver = "zfs";
      config."volume.zfs.blocksize" = "1MiB"; # capped to 128KiB for block volumes
      member.source = "${zpool "usb-"}/bulk";
    }
    {
      name = "ceph";
      driver = "ceph";
      config = {
        "ceph.cluster_name" = "ceph";
        "ceph.user.name" = "admin";
        "ceph.osd.pool_name" = "incus";
      };
      member = { };
    }
  ];

  withMember = map (e: removeAttrs e [ "member" ] // { config = e.config // e.member; });
  withoutMember = map (e: removeAttrs e [ "member" ]);
  memberConfig = entity: map (e: lib.mapAttrsToList (key: value: {
    inherit entity key value;
    inherit (e) name;
  }) e.member);

  # Cluster-wide state, applied on every member every start.
  preseed = {
    config."core.https_address" = ":8443";
    networks = withoutMember networks;
    storage_pools = withoutMember storagePools;

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

  # Single member, so the per host keys go straight onto the networks and pools.
  seedPreseed = preseed // {
    config = preseed.config // { "cluster.https_address" = address; };
    networks = withMember networks;
    storage_pools = withMember storagePools;
    cluster = {
      enabled = true;
      server_name = host;
    };
  };

  # cluster_token is filled in by the bootstrap script.
  joinPreseed.cluster = {
    enabled = true;
    server_name = host;
    server_address = address;
    member_config = lib.flatten (memberConfig "network" networks ++ memberConfig "storage-pool" storagePools);
  };

  bootstrapScript = pkgs.writeShellApplication {
    name = "incus-bootstrap";
    runtimeInputs = [ config.virtualisation.incus.package pkgs.jq pkgs.openssl pkgs.coreutils ];
    text = builtins.readFile ./scripts/incus-bootstrap.sh;
  };
in
{
  virtualisation.incus = {
    enable = true;
    ui.enable = true;
    package = pkgs.incus;
  };

  sops.secrets."incus-join-key" = {
    sopsFile = ../../secrets/compute.yaml;
    key = "incus-join-key";
  };

  # Bootstraps or joins the cluster, then applies the cluster-wide preseed.
  # Retries until a member hands out a token and the mons have quorum for the ceph pool, without blocking switch.
  systemd.services.incus-bootstrap = {
    description = "Incus cluster bootstrap and preseed";
    wantedBy = [ "incus.service" ];
    after = [ "incus.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    bindsTo = [ "incus.service" ];
    partOf = [ "incus.service" ];
    environment = {
      SERVER_NAME = host;
      SEED = seed;
      PEERS = toString (lib.attrValues (lib.filterAttrs (name: _: name != host) mesh.addresses));
      SEED_PRESEED = json.generate "incus-seed-preseed.json" seedPreseed;
      JOIN_PRESEED = json.generate "incus-join-preseed.json" joinPreseed;
      PRESEED = json.generate "incus-preseed.json" preseed;
      CERTIFICATES = toString (lib.mapAttrsToList (name: cert: "${name}=${cert}") certificates);
      JOIN_CERT = "${certificates.incus-join}";
      JOIN_KEY = config.sops.secrets."incus-join-key".path;
    };
    startLimitIntervalSec = 0;
    serviceConfig = {
      Type = "simple";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 15;
    };
    script = lib.getExe bootstrapScript;
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
