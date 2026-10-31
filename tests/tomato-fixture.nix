# A fake NixOS toplevel with the Tomato DTB set, small enough to pack and write in tests.
{ pkgs }:
rec {
  tools = pkgs.callPackage ../modules/hardware/tomato/tools.nix { };
  system = pkgs.runCommand "tomato-boot-fixture" { nativeBuildInputs = [ pkgs.dtc ]; } ''
    mkdir -p $out/dtbs/mediatek
    printf 'test ARM64 kernel payload\n' > $out/kernel
    printf 'test initramfs payload\n' > $out/initrd
    printf 'root=LABEL=TOMATO-USB rootwait console=ttyS0,115200n8' > $out/kernel-params
    for rev in 1 2 3; do
      compat="\"google,tomato-rev$rev\", \"google,tomato\", \"mediatek,mt8195\""
      if [ "$rev" = 3 ]; then
        compat="\"google,tomato-rev4\", $compat"
      fi
      printf '/dts-v1/; / { compatible = %s; };\n' "$compat" > board.dts
      dtc -I dts -O dtb board.dts -o "$out/dtbs/mediatek/mt8195-cherry-tomato-r$rev.dtb"
    done
  '';
  kernelImage = pkgs.runCommand "tomato-test-kernel.bin" { nativeBuildInputs = [ tools.pack ]; } ''
    tomato-pack-kernel ${system} $out
  '';
  rootfs = label: pkgs.runCommand "tomato-test-root.img" { nativeBuildInputs = [ pkgs.e2fsprogs ]; } ''
    truncate -s 16M $out
    mkdir files
    echo tomato-root-payload > files/marker
    mkfs.ext4 -L ${label} -d files $out
  '';
  # Same layout as installers/tomato-recovery.nix's system.build.tomatoRecovery.
  recovery = pkgs.runCommand "tomato-test-recovery" { nativeBuildInputs = [ pkgs.zstd ]; } ''
    mkdir -p $out
    cp ${kernelImage} $out/kernel.bin
    stat -c %s ${rootfs "tomato-recovery"} > $out/rootfs-size
    zstd --no-progress ${rootfs "tomato-recovery"} -o $out/rootfs.img.zst
  '';
}
