# A fake board and NixOS toplevel, small enough to pack and write in tests.
{ pkgs }:
rec {
  dtbs = map (rev: "vendor/board-r${toString rev}.dtb") [ 1 2 3 ];
  tools = pkgs.callPackage ../modules/hardware/chromebook/tools.nix { inherit dtbs; };
  system = pkgs.runCommand "chromebook-test-system" { nativeBuildInputs = [ pkgs.dtc ]; }
    (builtins.readFile ./chromebook-fixture.sh);
  kernelImage = pkgs.runCommand "chromebook-test-kernel.bin" { nativeBuildInputs = [ tools.pack ]; } ''
    chromebook-pack-kernel ${system} $out
  '';
  rootfs = label: pkgs.runCommand "chromebook-test-root.img" { nativeBuildInputs = [ pkgs.e2fsprogs ]; } ''
    truncate -s 16M $out
    mkdir files
    echo chromebook-root-payload > files/marker
    mkfs.ext4 -L ${label} -d files $out
  '';
  recovery = import ../modules/hardware/chromebook/recovery-bundle.nix {
    inherit pkgs kernelImage;
    name = "chromebook-test-recovery";
    rootfsImage = rootfs (import ../modules/hardware/chromebook/layout.nix).recovery;
  };
}
