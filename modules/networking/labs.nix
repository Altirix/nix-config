{ config, lib, ... }:

# An instance's leg on labs (VLAN 100, incus profile `default`). labs only reaches the router, instances are
# port isolated from each other and talk directly over labs-mesh instead. Live services take a static /32 with
# the router on-link, the hypervisors pin it to the instance of the same name (modules/compute.nix) so no other
# instance can claim it. Without one the bridge drops everything the instance sends (no labs network, reach it over
# vsock: `ssh incus-<name>`).
let
  cfg = config.homelab.labs;
  inherit (lib) mkOption types;
in
{
  options.homelab.labs = {
    # Bare IP, e.g. 10.100.2.20, its /24 is its trust zone (README.md). null: no labs network.
    # Always a /32, never the zone's /24 or labs' /16: with a wider mask the VM would ARP for its neighbours
    # directly, port isolation drops that, and traffic within a zone would vanish instead of passing the router.
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
    # Nothing hands out addresses, unpinned instances can't use labs anyway.
    { networking.useDHCP = false; }

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
