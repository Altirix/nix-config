{ lib, ... }:

{
  options.homelab.secrets = {
    # Shared by every host of a type (compute.nix, edge.nix ...), matches a group in .sops.yaml.
    groupFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
    };
  };
}
