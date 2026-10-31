{ config, lib, pkgs, ... }:

# USB installer. The flake adds the prebuilt Colluvium system (/etc/tomato-system),
# the recovery system (/etc/tomato-recovery) and a source snapshot (/etc/tomato-flake).
{
  imports = [ ./tomato-live.nix ];

  tomatoLive.rootLabel = "TOMATO-USB";
  networking.hostName = "tomato-installer";
  services.getty.helpLine = lib.mkForce "Tomato installer: SSH as admin with the repository's admin key.";

  system.build.tomatoDepthchargeImage = import ../modules/hardware/tomato/usb-image.nix {
    pkgs = pkgs.buildPackages;
    kernelImage = config.system.build.tomatoKernel;
    rootfsImage = config.system.build.tomatoRootfs;
  };
}
