{ config, lib, ... }:

# An instance's leg on labs-mesh, the VXLAN overlay instances use to reach each other across hosts
# (incus profile `labs-mesh`). The bridge hands out no addresses, so each instance picks a static one.
let
  cfg = config.homelab.labsMesh;
  inherit (lib) mkOption types;
in
{
  options.homelab.labsMesh = {
    # CIDR, e.g. 10.254.0.10/24. null leaves the interface down.
    address = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    ip = mkOption {
      type = types.str;
      readOnly = true;
      default = lib.head (lib.splitString "/" cfg.address);
    };

    # eth1 from the profile, the second NIC of an incus VM.
    interface = mkOption {
      type = types.str;
      default = "enp6s0";
    };
  };

  config = lib.mkIf (cfg.address != null) {
    networking.interfaces.${cfg.interface} = {
      useDHCP = false;
      ipv4.addresses = [{
        address = cfg.ip;
        prefixLength = lib.toInt (lib.last (lib.splitString "/" cfg.address));
      }];
    };
  };
}
