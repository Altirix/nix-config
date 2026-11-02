{ config, lib, pkgs, ... }:

# Recovery system in slot R, booted when kernel slots A and B both fail. Its root
# is a separate partition, so it does not depend on the NixOS root.
let
  layout = import ../../modules/hardware/chromebook/layout.nix;
in
{
  imports = [ ./live.nix ];

  chromebookLive.rootLabel = layout.recovery;
  services.getty.helpLine = lib.mkForce
    "Chromebook recovery: mount /dev/disk/by-label/${layout.root} on /mnt to redeploy, see modules/hardware/chromebook/README.md.";

  system.build.chromebookRecovery = import ../../modules/hardware/chromebook/recovery-bundle.nix {
    pkgs = pkgs.buildPackages;
    name = "${config.networking.hostName}-bundle";
    kernelImage = config.system.build.chromebookKernel;
    rootfsImage = config.system.build.chromebookRootfs;
  };
}
