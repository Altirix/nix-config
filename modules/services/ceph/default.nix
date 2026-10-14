{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.ceph;
  host = config.networking.hostName;
  ceph = pkgs.ceph;

  osds = lib.imap0 (i: device: {
    id = toString (cfg.osdIdBase + i);
    inherit device;
  }) cfg.osdDevices;

  bootstrapScript = name: runtimeInputs: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ ceph pkgs.coreutils ] ++ runtimeInputs;
    text = builtins.readFile ./scripts/${name}.sh;
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
  options.homelab.ceph = {
    enable = lib.mkEnableOption "a ceph mon, mgr and this host's OSDs";

    fsid = lib.mkOption { type = lib.types.str; };

    # Cluster-wide, name -> address.
    monitors = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
    };

    publicNetwork = lib.mkOption { type = lib.types.str; };

    clusterNetwork = lib.mkOption {
      type = lib.types.str;
      default = cfg.publicNetwork;
    };

    # Daemons bind here instead of letting ceph pick an interface.
    address = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    osdDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = config.homelab.storage.ceph.devices;
    };

    # OSD ids are osdIdBase + index into osdDevices, must not overlap between hosts.
    osdIdBase = lib.mkOption {
      type = lib.types.ints.unsigned;
    };

    # Holds [mon.] and [client.admin], seeds the mon auth database and serves as the admin keyring.
    keyringFile = lib.mkOption {
      type = lib.types.path;
      default = config.homelab.secrets.groupFile;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.monitors ? ${host};
      message = "ceph: every ceph host runs a mon, list it in homelab.ceph.monitors";
    }];

    services.ceph = {
      enable = true;
      client.enable = true; # puts the ceph client on incus' PATH

      global = {
        inherit (cfg) fsid;
        monInitialMembers = lib.concatStringsSep ", " (lib.attrNames cfg.monitors);
        monHost = lib.concatStringsSep ", " (lib.attrValues cfg.monitors);
        inherit (cfg) publicNetwork clusterNetwork;
      };

      extraConfig = {
        "auth_allow_insecure_global_id_reclaim" = "false";
      } // lib.optionalAttrs (cfg.address != null) {
        "public_addr" = cfg.address;
        "cluster_addr" = cfg.address;
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
        enable = osds != [ ];
        daemons = map (osd: osd.id) osds;
      };
    };

    environment.systemPackages = [ ceph ];

    sops.secrets."ceph-keyring" = {
      sopsFile = cfg.keyringFile;
      key = "ceph-keyring";
      path = "/etc/ceph/ceph.client.admin.keyring";
    };

    # Only the OSD partitions hold LVM, never activate VGs inside guest rbd/zvol disks.
    environment.etc."lvm/lvm.conf".text = lib.mkIf (osds != [ ]) ''
      devices/global_filter = [ ${lib.concatMapStrings (device: ''"a|^${device}$|", '') cfg.osdDevices}"r|.*|" ]
    '';

    systemd.tmpfiles.settings."10-ceph"."/var/log/ceph".d = {
      user = "ceph";
      group = "ceph";
    };

    systemd.services = {
      "ceph-mon-${host}-bootstrap" = bootstrap {
        daemon = "ceph-mon-${host}";
        script = bootstrapScript "ceph-mon-bootstrap" [ ];
        environment = {
          MON_ID = host;
          FSID = config.services.ceph.global.fsid;
          MONS = toString (lib.mapAttrsToList (name: ip: "${name}=${ip}") cfg.monitors);
          KEYRING = config.sops.secrets."ceph-keyring".path;
        };
      };

      "ceph-mgr-${host}-bootstrap" = bootstrap {
        daemon = "ceph-mgr-${host}";
        script = bootstrapScript "ceph-mgr-bootstrap" [ ];
        environment.MGR_ID = host;
      };
    }
    // lib.optionalAttrs (osds != [ ]) {
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
      script = bootstrapScript "ceph-osd-bootstrap" [ pkgs.lvm2 pkgs.util-linux ];
      environment = {
        OSD_ID = osd.id;
        OSD_DEVICE = osd.device;
      };
    })) osds);
  };
}
