{ config, lib, ... }:

# An instance's leg on labs (VLAN 100, incus profile `default`). labs only reaches the router, instances are
# port isolated from each other and talk directly over labs-mesh instead. Live services take a static /32 with
# the router on-link, the hypervisors pin it to the instance of the same name (modules/compute.nix) so no other
# instance can claim it. Without one the instance takes a lease from the router's setup pool.
let
  cfg = config.homelab.labs;
  inherit (lib) mkOption types;
in
{
  options.homelab.labs = {
    # Bare IP, e.g. 10.100.1.20, always a /32. null takes a DHCP lease from the setup pool.
    address = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    gateway = mkOption { type = types.str; };

    dns = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };

    # eth0 from the default profile, the first NIC of an incus VM.
    interface = mkOption {
      type = types.str;
      default = "enp5s0";
    };
  };

  config = lib.mkMerge [
    { networking.useDHCP = cfg.address == null; }

    (lib.mkIf (cfg.address != null) {
      networking = {
        interfaces.${cfg.interface}.ipv4 = {
          addresses = [{
            inherit (cfg) address;
            prefixLength = 32;
          }];
          # Added in order: the router on-link first, then the default route through it.
          routes = [
            {
              address = cfg.gateway;
              prefixLength = 32;
            }
            {
              address = "0.0.0.0";
              prefixLength = 0;
              via = cfg.gateway;
            }
          ];
        };
        nameservers = cfg.dns;
      };
    })
  ];
}
