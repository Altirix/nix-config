{ config, lib, pkgs, ... }:

let
  mesh = config.mesh;
  host = config.networking.hostName;
  ceph = pkgs.ceph;

  # Disko partitions named "ceph", numbered nodeId * 10 + index: andromeda gets osd.10, osd.11.
  osdDevices = lib.concatMap
    (disk: lib.optional (disk.content.partitions ? ceph) disk.content.partitions.ceph.device)
    (lib.attrValues config.disko.devices.disk);

  osds = lib.imap0 (i: device: {
    id = toString (mesh.nodeId * 10 + i);
    inherit device;
  }) osdDevices;

  bootstrapScript = name: runtimeInputs: pkgs.writeShellApplication {
    name = "ceph-${name}-bootstrap";
    runtimeInputs = [ ceph pkgs.coreutils ] ++ runtimeInputs;
    text = builtins.readFile ./scripts/ceph-${name}-bootstrap.sh;
  };

  # Daemons skip start until their keyring exists, these create it then start them.
  bootstrap = { daemon, script, environment }: {
    description = "Bootstrap ${daemon}";
    inherit environment;
    path = [ pkgs.systemd ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "ceph.target" ];
    # Retries until enough mons are up for quorum, without blocking switch.
    startLimitIntervalSec = 0;
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 15;
    };
    script = ''
      ${lib.getExe script}
      systemctl start --no-block ${daemon}.service
    '';
  };
in
{
  services.ceph = {
    enable = true;
    client.enable = true; # puts the ceph client on incus' PATH

    global = {
      fsid = "420bd11d-4495-4048-b8b0-4a84afbc25cb";
      monInitialMembers = lib.concatStringsSep ", " (lib.attrNames mesh.addresses);
      monHost = lib.concatStringsSep ", " (lib.attrValues mesh.addresses);
      publicNetwork = mesh.network;
      clusterNetwork = mesh.network;
    };

    # Bind to the loopback address so a single dead mesh link doesn't move the daemon.
    extraConfig = {
      "public_addr" = mesh.routerIp;
      "cluster_addr" = mesh.routerIp;
      "auth_allow_insecure_global_id_reclaim" = "false";
    };

    mon = {
      enable = true;
      daemons = [ host ];
    };

    mgr = {
      enable = true;
      daemons = [ host ];
    };

    osd = {
      enable = true;
      daemons = map (osd: osd.id) osds;
    };
  };

  environment.systemPackages = [ ceph ];

  # Holds [mon.] and [client.admin], seeds the mon auth database and serves as the admin keyring.
  sops.secrets."ceph-keyring" = {
    sopsFile = ../../secrets/compute.yaml;
    key = "ceph-keyring";
    path = "/etc/ceph/ceph.client.admin.keyring";
  };

  # Only the OSD partitions hold LVM, never activate VGs inside guest rbd/zvol disks.
  environment.etc."lvm/lvm.conf".text = ''
    devices/global_filter = [ ${lib.concatMapStrings (device: ''"a|^${device}$|", '') osdDevices}"r|.*|" ]
  '';

  systemd.tmpfiles.settings."10-ceph"."/var/log/ceph".d = {
    user = "ceph";
    group = "ceph";
  };

  systemd.services = {
    "ceph-mon-${host}-bootstrap" = bootstrap {
      daemon = "ceph-mon-${host}";
      script = bootstrapScript "mon" [ ];
      environment = {
        MON_ID = host;
        FSID = config.services.ceph.global.fsid;
        MONS = toString (lib.mapAttrsToList (name: ip: "${name}=${ip}") mesh.addresses);
        KEYRING = config.sops.secrets."ceph-keyring".path;
      };
    };

    "ceph-mgr-${host}-bootstrap" = bootstrap {
      daemon = "ceph-mgr-${host}";
      script = bootstrapScript "mgr" [ ];
      environment.MGR_ID = host;
    };

    # OSD dirs are tmpfs, so ceph-volume has to rebuild them every boot.
    "ceph-osd-activate" = {
      description = "Activate Ceph OSDs";
      path = [ ceph pkgs.lvm2 pkgs.util-linux pkgs.coreutils ];
      after = [ "local-fs.target" ];
      before = map (osd: "ceph-osd-${osd.id}.service") osds;
      requiredBy = map (osd: "ceph-osd-${osd.id}.service") osds;
      restartIfChanged = false; # re-running under live OSDs remounts their dirs
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = "ceph-volume lvm activate --all --no-systemd";
    };
  }
  // lib.listToAttrs (map (osd: lib.nameValuePair "ceph-osd-${osd.id}-bootstrap" (bootstrap {
    daemon = "ceph-osd-${osd.id}";
    script = bootstrapScript "osd" [ pkgs.lvm2 pkgs.util-linux ];
    environment = {
      OSD_ID = osd.id;
      OSD_DEVICE = osd.device;
    };
  })) osds);
}
