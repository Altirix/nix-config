{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.incus;
  host = config.networking.hostName;
  json = pkgs.formats.json { };
  inherit (lib) mkOption types;

  entities = types.listOf (types.attrsOf types.anything);
  memberKeys = types.attrsOf (types.attrsOf types.str);

  address = "${cfg.cluster.address}:8443";

  # Trusted cluster-wide, re-adding one through preseed fails, so the bootstrap adds missing ones.
  certificates = cfg.trustedCertificates // {
    incus-join = cfg.joinCertificate; # lets a new member fetch its own join token
  };

  member = kind: e: cfg.members.${kind}.${e.name} or { };
  withMember = kind: map (e: e // { config = e.config // member kind e; });
  memberConfig = kind: entity: map (e: lib.mapAttrsToList (key: value: {
    inherit entity key value;
    inherit (e) name;
  }) (member kind e));

  # Cluster-wide state, applied on every member every start.
  preseed = {
    config = cfg.config // { "core.https_address" = ":8443"; };
    inherit (cfg) networks profiles projects;
    storage_pools = cfg.storagePools;
  };

  # Single member, so the per host keys go straight onto the networks and pools.
  seedPreseed = preseed // {
    config = preseed.config // { "cluster.https_address" = address; };
    networks = withMember "networks" cfg.networks;
    storage_pools = withMember "storagePools" cfg.storagePools;
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
    member_config = lib.flatten (memberConfig "networks" "network" cfg.networks
      ++ memberConfig "storagePools" "storage-pool" cfg.storagePools);
  };

  # Bridges and their uplinks, instances only ever live behind these.
  instanceInterfaces = lib.concatMap (n:
    [ n.name ] ++ lib.optional (member "networks" n ? "bridge.external_interfaces")
      (member "networks" n)."bridge.external_interfaces")
    cfg.networks;

  bootstrapScript = pkgs.writeShellApplication {
    name = "incus-bootstrap";
    runtimeInputs = [ config.virtualisation.incus.package pkgs.jq pkgs.openssl pkgs.coreutils ];
    text = builtins.readFile ./scripts/incus-bootstrap.sh;
  };
in
{
  options.homelab.incus = {
    enable = lib.mkEnableOption "an incus cluster member";

    cluster = {
      # This member's address, peers reach it here.
      address = mkOption { type = types.str; };

      # Every member, name -> address.
      members = mkOption { type = types.attrsOf types.str; };

      # Creates the cluster, everyone else joins it.
      seed = mkOption { type = types.str; };
    };

    # networks, storagePools, projects and profiles are cluster-wide, the same on every member.
    # Per host keys go in `members`.
    networks = mkOption {
      type = entities;
      default = [ ];
    };

    storagePools = mkOption {
      type = entities;
      default = [ ];
    };

    projects = mkOption {
      type = entities;
      default = [ ];
    };

    profiles = mkOption {
      type = entities;
      default = [ ];
    };

    # Per host keys, set on create and through member_config on join, never in the cluster-wide preseed.
    members = {
      networks = mkOption {
        type = memberKeys;
        default = { };
        example = { labs."bridge.external_interfaces" = "labs-uplink"; };
      };
      storagePools = mkOption {
        type = memberKeys;
        default = { };
        example = { nvme.source = "nvme-zfs-mirror2/vm"; };
      };
    };

    # Server config (`incus config set`), cluster-wide. Merged into the live config, a key dropped here stays set.
    config = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { "authorization.client.tls-restricted" = "scriptlet"; };
    };

    trustedCertificates = mkOption {
      type = types.attrsOf types.path;
      default = { };
    };

    # Trusted only in `projects`, authorized by whatever authorization.client.tls-restricted routes to.
    # Like trustedCertificates, one dropped here stays trusted until `incus config trust remove`.
    restrictedCertificates = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          certificate = mkOption { type = types.path; };
          projects = mkOption { type = types.nonEmptyListOf types.str; };
        };
      });
      default = { };
    };

    joinCertificate = mkOption { type = types.path; };

    joinKeyFile = mkOption {
      type = types.path;
      default = config.homelab.secrets.groupFile;
      description = "sops file holding incus-join-key.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.cluster.members ? ${cfg.cluster.seed};
        message = "incus: cluster.seed must be one of cluster.members";
      }
      {
        assertion = lib.all (name: lib.elem name (map (e: e.name) cfg.networks)) (lib.attrNames cfg.members.networks)
          && lib.all (name: lib.elem name (map (e: e.name) cfg.storagePools)) (lib.attrNames cfg.members.storagePools);
        message = "incus: members.* names a network or storage pool that isn't defined";
      }
    ];

    virtualisation.incus = {
      enable = true;
      ui.enable = true;
      package = pkgs.incus;
    };

    sops.secrets."incus-join-key" = {
      sopsFile = cfg.joinKeyFile;
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
        SEED = cfg.cluster.seed;
        PEERS = toString (lib.attrValues (lib.filterAttrs (name: _: name != host) cfg.cluster.members));
        SEED_PRESEED = json.generate "incus-seed-preseed.json" seedPreseed;
        JOIN_PRESEED = json.generate "incus-join-preseed.json" joinPreseed;
        PRESEED = json.generate "incus-preseed.json" preseed;
        CERTIFICATES = toString (lib.mapAttrsToList (name: cert: "${name}=${cert}") certificates);
        RESTRICTED_CERTIFICATES = toString (lib.mapAttrsToList (name: c:
          "${name}=${lib.concatStringsSep "," c.projects}=${c.certificate}") cfg.restrictedCertificates);
        JOIN_CERT = "${cfg.joinCertificate}";
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
    boot.kernelModules = lib.mkIf (lib.any (pool: pool.driver or null == "ceph") cfg.storagePools) [ "rbd" ];

    # Hosts never talk to or route for instance networks, so instances can't reach mgmt or ceph.
    networking.nftables.tables.instance-isolation = {
      family = "inet";
      content = builtins.replaceStrings
        [ "@interfaces@" ]
        [ "{ ${lib.concatMapStringsSep ", " (i: ''"${i}"'') instanceInterfaces} }" ]
        (builtins.readFile ./config/instance-isolation.nft);
    };

    networking.firewall.interfaces = lib.genAttrs config.homelab.lan.adminInterfaces (_: {
      allowedTCPPorts = [ 8443 ];
    });
    users.users.admin.extraGroups = [ "incus-admin" ];
  };
}
