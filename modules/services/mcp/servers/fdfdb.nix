{ lib, pkgs, ... }:

# NAND flash by part number or flash ID, with the controllers that support it, from iTXTech's fdfdb
# (packages/fdfdb.nix). Read-only and offline: the index is built into the store, the server reaches nothing.
{
  homelab.mcp.servers.fdfdb = {
    command = lib.mkDefault (lib.getExe (pkgs.callPackage ../packages/fdfdb.nix { }));
    port = lib.mkDefault 8110;
  };
}
