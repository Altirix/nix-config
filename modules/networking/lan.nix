{ config, lib, ... }:

# A trunk port carrying tagged VLANs, nothing untagged.
let
  cfg = config.homelab.lan;
  inherit (lib) mkOption types;

  vlan = types.submodule {
    options = {
      id = mkOption { type = types.ints.between 1 4094; };

      # Unaddressed VLANs are bridge uplinks only, the host never talks on them.
      address = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      gateway = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      dns = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      # SSH and admin UIs are only reachable on these.
      admin = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  vlanNetwork = name: v:
    if v.address == null then {
      matchConfig.Name = name;
      networkConfig.LinkLocalAddressing = "no";
    } else {
      matchConfig.Name = name;
      address = [ v.address ];
      inherit (v) dns;
      networkConfig.DHCP = "no";
    }
    // lib.optionalAttrs (v.gateway != null) { routes = [ { Gateway = v.gateway; } ]; }
    // lib.optionalAttrs (v.domain != null) { domains = [ v.domain ]; };
in
{
  options.homelab.lan = {
    enable = lib.mkEnableOption "VLAN trunk networking";

    interface = mkOption { type = types.str; };

    # Keyed by interface name, IFNAMSIZ caps them at 15 chars.
    vlans = mkOption {
      type = types.attrsOf vlan;
      default = { };
    };

    adminInterfaces = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = lib.attrNames (lib.filterAttrs (_: v: v.admin) cfg.vlans);
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.allUnique (lib.mapAttrsToList (_: v: v.id) cfg.vlans);
        message = "lan: every VLAN needs its own id";
      }
      {
        assertion = lib.all (name: lib.stringLength name <= 15) (lib.attrNames cfg.vlans);
        message = "lan: VLAN interface names are capped at 15 chars";
      }
    ];

    networking.nftables.enable = true;
    networking.firewall.enable = true;

    networking.useDHCP = false;
    networking.useNetworkd = true;
    systemd.network.enable = true;

    systemd.network.netdevs = lib.mapAttrs (name: v: {
      netdevConfig = {
        Kind = "vlan";
        Name = name;
      };
      vlanConfig.Id = v.id;
    }) cfg.vlans;

    systemd.network.networks = lib.mapAttrs vlanNetwork cfg.vlans // {
      "lan" = {
        matchConfig.Name = cfg.interface;
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
        vlan = lib.attrNames cfg.vlans;
      };
    };

    networking.firewall.interfaces = lib.genAttrs cfg.adminInterfaces (_: {
      allowedTCPPorts = [ 22 ];
    });
  };
}
