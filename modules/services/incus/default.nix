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
    config."core.https_address" = ":8443";
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
  uplinks = lib.concatMap (n: lib.splitString "," (member "networks" n)."bridge.external_interfaces")
    (lib.filter (n: member "networks" n ? "bridge.external_interfaces") cfg.networks);
  instanceInterfaces = map (n: n.name) cfg.networks ++ uplinks;
  bridges = map (n: n.name) (lib.filter (n: n.type or "bridge" == "bridge") cfg.networks);

  nftSet = names: "{ ${lib.concatMapStringsSep ", " (i: ''"${i}"'') names} }";

  # Answer file, first logon scripts and the virtio guest drivers. The install ISO stays as Microsoft ships it,
  # the root disk is nvme and the media usb, which Windows has inbox drivers for.
  autounattend = pkgs.writeText "autounattend.xml" (builtins.replaceStrings
    [ "@language@" ]
    [ cfg.windows.language ]
    (builtins.readFile ./config/windows/autounattend.xml));
  windowsUnattend = pkgs.runCommand "windows-unattend.iso" { nativeBuildInputs = [ pkgs.xorriso ]; } ''
    mkdir root
    cp ${autounattend} root/autounattend.xml
    cp ${./scripts/windows/setup.ps1} root/setup.ps1
    cp ${./scripts/windows/debloat.ps1} root/debloat.ps1
    cp ${pkgs.virtio-win}/virtio-win-gt-x64.msi root/
    xorriso -as mkisofs -J -R -V UNATTEND -o $out root
  '';

  windowsAutobootScript = pkgs.writeShellApplication {
    name = "incus-windows-autoboot";
    runtimeInputs = [ config.virtualisation.incus.package pkgs.jq pkgs.socat pkgs.coreutils ];
    runtimeEnv.SELF = host;
    text = builtins.readFile ./scripts/incus-windows-autoboot.sh;
  };

  bootstrapScript = pkgs.writeShellApplication {
    name = "incus-bootstrap";
    runtimeInputs = [ config.virtualisation.incus.package pkgs.jq pkgs.openssl pkgs.coreutils ];
    text = builtins.readFile ./scripts/incus-bootstrap.sh;
  };

  # Other members reach this member's VMs through the relay, see incus-ssh-proxy.sh.
  relayPort = 2222;
  peers = lib.filterAttrs (name: _: name != host) cfg.cluster.members;

  sshProxyScript = pkgs.writeShellApplication {
    name = "incus-ssh-proxy";
    runtimeInputs = [ config.virtualisation.incus.package pkgs.jq pkgs.coreutils pkgs.socat ];
    runtimeEnv = {
      SELF = host;
      MEMBERS = toString (lib.mapAttrsToList (name: address: "${name}=${address}") cfg.cluster.members);
      RELAY_PORT = toString relayPort;
    };
    text = builtins.readFile ./scripts/incus-ssh-proxy.sh;
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

    # Instance -> profiles it must carry (an address pin), the bootstrap adds them once the instance exists.
    instanceProfiles = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = { };
    };

    windows = {
      pool = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Pool the Windows unattend ISO is imported into as `windows-unattend`, a remote one so every member sees it. null skips it.";
      };

      language = mkOption {
        type = types.str;
        default = "en-GB";
        description = "Windows setup and display language, the install ISO has to carry it (en-GB is \"English International\").";
      };
    };

    trustedCertificates = mkOption {
      type = types.attrsOf types.path;
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
      {
        assertion = lib.allUnique (map (p: p.name) cfg.profiles);
        message = "incus: profile names must be unique";
      }
      {
        assertion = lib.all (name: lib.elem name (map (p: p.name) cfg.profiles)) (lib.concatLists (lib.attrValues cfg.instanceProfiles));
        message = "incus: instanceProfiles names a profile that isn't defined";
      }
      {
        assertion = cfg.windows.pool == null || lib.elem cfg.windows.pool (map (p: p.name) cfg.storagePools);
        message = "incus: windows.pool names a storage pool that isn't defined";
      }
      {
        assertion = cfg.windows.pool == null || lib.any (p: p.name == cfg.windows.pool && p.driver == "ceph") cfg.storagePools;
        message = "incus: windows.pool has to be a ceph pool, every member imports into it";
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

    # Bootstraps or joins the cluster, applies the cluster-wide preseed, then the instance profiles.
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
        PEERS = toString (lib.attrValues peers);
        SEED_PRESEED = json.generate "incus-seed-preseed.json" seedPreseed;
        JOIN_PRESEED = json.generate "incus-join-preseed.json" joinPreseed;
        PRESEED = json.generate "incus-preseed.json" preseed;
        CERTIFICATES = toString (lib.mapAttrsToList (name: cert: "${name}=${cert}") certificates);
        INSTANCE_PROFILES = toString (lib.mapAttrsToList (name: profiles: "${name}=${lib.concatStringsSep "," profiles}") cfg.instanceProfiles);
        WINDOWS_UNATTEND = lib.optionalString (cfg.windows.pool != null) "${cfg.windows.pool} windows-unattend ${windowsUnattend}";
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

    # Answers "Press any key to boot from CD or DVD" for Windows VMs installing, see scripts/incus-windows-autoboot.sh.
    systemd.services.incus-windows-autoboot = lib.mkIf (cfg.windows.pool != null) {
      description = "Boot Windows VMs from their install media";
      wantedBy = [ "incus.service" ];
      after = [ "incus.service" ];
      bindsTo = [ "incus.service" ];
      serviceConfig = {
        ExecStart = lib.getExe windowsAutobootScript;
        Restart = "always";
        RestartSec = 5;
      };
    };

    # `ssh incus-<instance>` reaches a VM on any member over vsock, also as a nixos-anywhere target.
    # On PATH so other machines can use it as `ProxyCommand ssh admin@<member> incus-ssh-proxy %h %p`.
    # Host keys aren't pinned, an installer makes new ones every boot and vsock never leaves the cluster.
    environment.systemPackages = [ sshProxyScript ];
    programs.ssh.extraConfig = ''
      Host incus-*
        ProxyCommand ${lib.getExe sshProxyScript} %h %p
        CheckHostIP no
        StrictHostKeyChecking no
        UserKnownHostsFile /dev/null
    '';

    # Relay for the other members, only reaches sshd of VMs on this member. Mesh only, peers only.
    systemd.sockets.incus-ssh-relay = {
      description = "Relay ssh to local incus VMs for other members";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ "${cfg.cluster.address}:${toString relayPort}" ];
      socketConfig = {
        Accept = true;
        FreeBind = true;
        IPAddressDeny = "any";
        IPAddressAllow = lib.attrValues peers;
        MaxConnectionsPerSource = 16;
      };
    };

    systemd.services."incus-ssh-relay@" = {
      description = "Relay ssh to a local incus VM";
      serviceConfig = {
        ExecStart = "${lib.getExe sshProxyScript} --serve";
        StandardInput = "socket";
        StandardError = "journal";
        DynamicUser = true;
        SupplementaryGroups = [ "incus-admin" ];
        # Only the incus socket and vsock, the connection itself comes from the socket unit.
        RestrictAddressFamilies = [ "AF_UNIX" "AF_VSOCK" ];
        # The incus client wants a writable config dir, DynamicUser gives each connection its own /tmp.
        Environment = [ "INCUS_CONF=/tmp/incus" ];
      };
    };

    # Incus maps rbd volumes through the kernel client.
    boot.kernelModules = lib.mkIf (lib.any (pool: pool.driver or null == "ceph") cfg.storagePools) [ "rbd" ];

    # The default qemu has no ceph support, so VMs with an ISO or disk on ceph won't boot. qemu_full has it.
    nixpkgs.overlays = [ (final: _: { qemu_kvm = final.qemu_full; }) ];

    # Hosts never talk to or route for instance networks, so instances can't reach mgmt or ceph.
    networking.nftables.tables.instance-isolation = {
      family = "inet";
      content = builtins.replaceStrings
        [ "@interfaces@" ]
        [ (nftSet instanceInterfaces) ]
        (builtins.readFile ./config/instance-isolation.nft);
    };

    # Instances share L2, so stop one from posing as the router to the others (rogue DHCP, RAs).
    # MAC and ARP spoofing are handled per NIC by incus, see security.mac_filtering in the profiles.
    networking.nftables.tables.instance-guard = lib.mkIf (bridges != [ ]) {
      family = "bridge";
      content = builtins.replaceStrings
        [ "@bridges@" "@fromInstance@" ]
        [ (nftSet bridges) (lib.optionalString (uplinks != [ ]) "iifname != ${nftSet uplinks} ") ]
        (builtins.readFile ./config/instance-guard.nft);
    };

    # The incus module loads br_netfilter, which sends bridged frames through the inet hooks as iifname/oifname
    # = the bridge, so the drops above would eat all instance traffic, DHCP included. Bridged stays L2 only.
    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-iptables" = 0;
      "net.bridge.bridge-nf-call-ip6tables" = 0;
      "net.bridge.bridge-nf-call-arptables" = 0;
    };

    networking.firewall.interfaces = lib.genAttrs config.homelab.lan.adminInterfaces (_: {
      allowedTCPPorts = [ 8443 ];
    });
    users.users.admin.extraGroups = [ "incus-admin" ];
  };
}
