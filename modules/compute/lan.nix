{ config, lib, ... }:

let
  cfg = config.lan;

  vlanNetdev = name: id: {
    netdevConfig = {
      Kind = "vlan";
      Name = name;
    };
    vlanConfig.Id = id;
  };
in
{
  options.lan = {
    interface = lib.mkOption {
      type = lib.types.str;
    };

    mgmt = {
      vlan = lib.mkOption { type = lib.types.ints.between 1 4094; };
      address = lib.mkOption { type = lib.types.str; };
      gateway = lib.mkOption { type = lib.types.str; };
      dns = lib.mkOption { type = lib.types.listOf lib.types.str; };
      domain = lib.mkOption { type = lib.types.str; };
    };

    labs = {
      vlan = lib.mkOption { type = lib.types.ints.between 1 4094; };
    };

    # Untagged address, takes the default route while set.
    fallback = lib.mkOption {
      default = null;
      type = lib.types.nullOr (lib.types.submodule {
        options = {
          address = lib.mkOption { type = lib.types.str; };
          gateway = lib.mkOption { type = lib.types.str; };
        };
      });
    };

    # Instances bridge onto this, so they never see mgmt or untagged traffic.
    labsUplink = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "labs-uplink";
    };

    adminInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = [ "mgmt" ] ++ lib.optional (cfg.fallback != null) cfg.interface;
    };
  };

  config = {
    assertions = [{
      assertion = cfg.mgmt.vlan != cfg.labs.vlan;
      message = "lan: mgmt and labs must use different VLANs";
    }];

    networking.nftables.enable = true;
    networking.firewall.enable = true;

    networking.useDHCP = false;
    networking.useNetworkd = true;
    systemd.network.enable = true;

    systemd.network.netdevs = {
      "mgmt" = vlanNetdev "mgmt" cfg.mgmt.vlan;
      ${cfg.labsUplink} = vlanNetdev cfg.labsUplink cfg.labs.vlan;
    };

    systemd.network.networks = {
      "lan" = {
        matchConfig.Name = cfg.interface;
        networkConfig = {
          DHCP = "no";
          LinkLocalAddressing = "no";
        };
        vlan = [ "mgmt" cfg.labsUplink ];
      } // lib.optionalAttrs (cfg.fallback != null) {
        address = [ cfg.fallback.address ];
        routes = [{ Gateway = cfg.fallback.gateway; }];
        dns = [ cfg.fallback.gateway ];
      };

      "mgmt" = {
        matchConfig.Name = "mgmt";
        address = [ cfg.mgmt.address ];
        routes = lib.optional (cfg.fallback == null) { Gateway = cfg.mgmt.gateway; };
        dns = cfg.mgmt.dns;
        domains = [ cfg.mgmt.domain ];
        networkConfig.DHCP = "no";
      };

      # Incus bridge uplink, no host address.
      ${cfg.labsUplink} = {
        matchConfig.Name = cfg.labsUplink;
        networkConfig.LinkLocalAddressing = "no";
      };
    };

    networking.firewall.interfaces = lib.genAttrs cfg.adminInterfaces (_: {
      allowedTCPPorts = [ 22 ];
    });
  };
}
