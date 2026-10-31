{ config, lib, pkgs, ... }:

# eMMC recovery system in slot R, booted when kernel slots A and B both fail.
# Its root is a separate partition, so it does not depend on the main root.
{
  imports = [ ./tomato-live.nix ];

  tomatoLive.rootLabel = "tomato-recovery";
  networking.hostName = "tomato-recovery";
  services.getty.helpLine = lib.mkForce "Tomato recovery: mount /dev/disk/by-label/tomato-root on /mnt to redeploy, see hosts/sbc/tomato.md.";

  # Written by tomato-install-recovery: the signed kernel for slot R and the
  # compressed root filesystem, grown to fill its partition when written.
  system.build.tomatoRecovery = pkgs.buildPackages.runCommand "tomato-recovery" {
    nativeBuildInputs = [ pkgs.buildPackages.zstd ];
  } ''
    mkdir -p $out
    cp ${config.system.build.tomatoKernel} $out/kernel.bin
    stat -c %s ${config.system.build.tomatoRootfs} > $out/rootfs-size
    zstd -T$NIX_BUILD_CORES --no-progress ${config.system.build.tomatoRootfs} -o $out/rootfs.img.zst
  '';
}
