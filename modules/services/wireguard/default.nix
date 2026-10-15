{ config, lib, ... }:

# A WireGuard hub through systemd-networkd, keys come from sops. Routes between peers,
# optionally NATs them out to the internet and forwards public ports to them.
let
  cfg = config.homelab.wireguard;
  inherit (lib) mkOption types;

  pskSecret = name: "wireguard-psk-${name}";

  peer = types.submodule {
    options = {
      publicKey = mkOption { type = types.str; };
      allowedIPs = mkOption { type = types.listOf types.str; };
      endpoint = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      persistentKeepalive = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
      };
      # Reads wireguard-psk-<peer> from `keyFile`.
      presharedKey = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  forward = types.submodule {
    options = {
      proto = mkOption { type = types.enum [ "tcp" "udp" ]; };
      # A port or a range ("27015-27030").
      port = mkOption { type = types.either types.port (types.strMatching "[0-9]+-[0-9]+"); };
      to = mkOption { type = types.str; };
      # Port on the peer, the same as `port` when unset. A range shifts one to one, starting here.
      toPort = mkOption {
        type = types.nullOr types.port;
        default = null;
      };
      # Arrives from this host's tunnel address, so replies find their way back without help.
      # Off keeps the client's address, the peer then has to route replies back through the tunnel.
      masquerade = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  key = f: "${f.proto} . ${toString f.port}";
  elements = xs: lib.optionalString (xs != [ ]) "elements = { ${lib.concatStringsSep ", " xs} }";

  low = f: if builtins.isInt f.port then f.port else lib.toInt (lib.head (lib.splitString "-" f.port));
  high = f: if builtins.isInt f.port then f.port else lib.toInt (lib.last (lib.splitString "-" f.port));
  covers = f: port: low f <= port && port <= high f;
  overlap = a: b: a.proto == b.proto && low a <= high b && low b <= high a;

  # nftables can't shift a range, so a remapped range becomes one entry per port.
  remapped = f: map (p: "${f.proto} . ${toString p} : ${f.to} . ${toString (f.toPort + p - low f)}") (lib.range (low f) (high f));
  samePort = lib.filter (f: f.toPort == null) cfg.forwards;

  withInterface = file: builtins.replaceStrings [ "@interface@" ] [ cfg.interface ] (builtins.readFile file);

  tunnelAddresses = map (a: lib.head (lib.splitString "/" a)) (lib.filter (a: !lib.hasInfix ":" a) cfg.address);

  pskPeers = lib.attrNames (lib.filterAttrs (_: p: p.presharedKey) cfg.peers);
in
{
  options.homelab.wireguard = {
    enable = lib.mkEnableOption "a WireGuard interface";

    interface = mkOption {
      type = types.str;
      default = "wg0";
    };

    address = mkOption { type = types.listOf types.str; };

    listenPort = mkOption {
      type = types.port;
      default = 51820;
    };

    # WireGuard's default, clients use the same unless told otherwise.
    mtu = mkOption {
      type = types.ints.between 1280 1500;
      default = 1420;
    };

    # Peers can use this host as their way out to the internet (masqueraded behind its address).
    egress = mkOption {
      type = types.bool;
      default = false;
    };

    # Public ports DNATed to a peer (or anything it routes).
    forwards = mkOption {
      type = types.listOf forward;
      default = [ ];
    };

    # Name -> peer, the name only picks the preshared key secret.
    peers = mkOption {
      type = types.attrsOf peer;
      default = { };
    };

    keyFile = mkOption {
      type = types.path;
      default = config.sops.defaultSopsFile;
      description = "sops file holding wireguard-private-key and wireguard-psk-<peer>.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !lib.any (f: f.proto == "tcp" && covers f 22 || f.proto == "udp" && covers f cfg.listenPort) cfg.forwards;
        message = "wireguard: a forward would take over SSH or the WireGuard port";
      }
      {
        assertion = lib.all (i: lib.all (j: !overlap (lib.elemAt cfg.forwards i) (lib.elemAt cfg.forwards j))
          (lib.range (i + 1) (lib.length cfg.forwards - 1))) (lib.range 0 (lib.length cfg.forwards - 1));
        message = "wireguard: two forwards share a port";
      }
      {
        assertion = lib.all (f: f.toPort == null || f.toPort + high f - low f <= 65535) cfg.forwards;
        message = "wireguard: a remapped range runs past port 65535";
      }
    ];

    sops.secrets = lib.genAttrs ([ "wireguard-private-key" ] ++ map pskSecret pskPeers) (key: {
      sopsFile = cfg.keyFile;
      inherit key;
      owner = "systemd-network";
      restartUnits = [ "systemd-networkd.service" ];
    });

    networking.useNetworkd = true;

    systemd.network.netdevs.${cfg.interface} = {
      netdevConfig = {
        Kind = "wireguard";
        Name = cfg.interface;
        MTUBytes = toString cfg.mtu;
      };
      wireguardConfig = {
        PrivateKeyFile = config.sops.secrets."wireguard-private-key".path;
        ListenPort = cfg.listenPort;
        # Routes every peer's AllowedIPs, never give a peer 0.0.0.0/0.
        RouteTable = "main";
      };
      wireguardPeers = lib.mapAttrsToList (name: p: {
        PublicKey = p.publicKey;
        AllowedIPs = p.allowedIPs;
      }
      // lib.optionalAttrs (p.endpoint != null) { Endpoint = p.endpoint; }
      // lib.optionalAttrs (p.persistentKeepalive != null) { PersistentKeepalive = p.persistentKeepalive; }
      // lib.optionalAttrs p.presharedKey { PresharedKeyFile = config.sops.secrets.${pskSecret name}.path; }) cfg.peers;
    };

    systemd.network.networks.${cfg.interface} = {
      matchConfig.Name = cfg.interface;
      inherit (cfg) address;
    };

    networking.firewall.allowedUDPPorts = [ cfg.listenPort ];

    # Forwarding is deny by default: peers to each other, peers out (egress), forwarded ports in (the
    # firewall accepts `ct status dnat` itself) and replies.
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    networking.firewall.filterForward = true;
    networking.firewall.extraForwardRules = lib.mkMerge [
      (withInterface ./config/allow-peers.nft)
      (lib.mkIf cfg.egress (withInterface ./config/allow-egress.nft))
    ];

    networking.nftables.tables.wireguard-forwards = lib.mkIf (cfg.forwards != [ ]) {
      family = "ip";
      content = builtins.replaceStrings
        [ "@interface@" "@tunnelAddresses@" "@forwards@" "@forwardsRemapped@" "@masqueraded@" ]
        [
          cfg.interface
          (lib.concatStringsSep ", " tunnelAddresses)
          (elements (map (f: "${key f} : ${f.to}") samePort))
          (elements (lib.concatMap remapped (lib.filter (f: f.toPort != null) cfg.forwards)))
          (elements (map key (lib.filter (f: f.masquerade) cfg.forwards)))
        ]
        (builtins.readFile ./config/forwards.nft);
    };

    networking.nftables.tables.wireguard-mss = {
      family = "ip";
      content = builtins.replaceStrings
        [ "@interface@" "@mss@" ]
        [ cfg.interface (toString (cfg.mtu - 40)) ] # minus IPv4 and TCP headers
        (builtins.readFile ./config/mss.nft);
    };

    networking.nftables.tables.wireguard-egress = lib.mkIf cfg.egress {
      family = "ip";
      content = withInterface ./config/egress.nft;
    };
  };
}
