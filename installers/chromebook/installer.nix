{ config, lib, pkgs, ... }:

# USB installer. The flake adds the board, the prebuilt host system (/etc/chromebook-system),
# the recovery bundle (/etc/chromebook-recovery) and a source snapshot (/etc/chromebook-flake).
let
  layout = import ../../modules/hardware/chromebook/layout.nix;
  install = pkgs.writeShellApplication {
    name = "chromebook-install";
    runtimeInputs = [
      pkgs.coreutils pkgs.util-linux pkgs.e2fsprogs config.system.build.nixos-install
      config.system.build.chromebookTools.partition config.system.build.chromebookTools.installRecovery
    ];
    text = builtins.replaceStrings [ "@root@" ] [ layout.root ] (builtins.readFile ./install.sh);
  };
in
{
  imports = [ ./live.nix ];

  chromebookLive.rootLabel = layout.usbRoot;
  environment.systemPackages = [ install ];
  services.getty.helpLine = lib.mkForce "Chromebook installer: SSH as admin with the repository's admin key.";

  system.build.chromebookUsbImage = import ../../modules/hardware/chromebook/usb-image.nix {
    pkgs = pkgs.buildPackages;
    name = "${config.networking.hostName}-image";
    kernelImage = config.system.build.chromebookKernel;
    rootfsImage = config.system.build.chromebookRootfs;
  };
}
