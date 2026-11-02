# Host-side checks of the signed kernel, USB image and recovery bundle formats,
# using a fake board. They do not emulate Depthcharge.
{ pkgs }:
let
  fixtures = import ./chromebook-fixture.nix { inherit pkgs; };
  layout = import ../modules/hardware/chromebook/layout.nix;
  rootfsImage = fixtures.rootfs layout.usbRoot;
in
pkgs.runCommand "chromebook-boot-contract" {
  inherit rootfsImage;
  inherit (fixtures) kernelImage;
  fixture = fixtures.system;
  recovery = fixtures.recovery;
  usbImage = import ../modules/hardware/chromebook/usb-image.nix {
    inherit pkgs rootfsImage;
    inherit (fixtures) kernelImage;
    name = "chromebook-test-image";
    rootExtraSpaceMiB = 16;
  };
  devkeys = "${pkgs.vboot-utils}/share/vboot/devkeys";
  # The recovery bundle is written raw and must not keep its system's closure alive.
  exportReferencesGraph = [ "recovery-graph" fixtures.recovery ];
  nativeBuildInputs = with fixtures.tools; [ pack install ]
    ++ [ pkgs.vboot-utils pkgs.ubootTools pkgs.dtc pkgs.gptfdisk pkgs.e2fsprogs ];
} (builtins.readFile ./chromebook-contract.sh)
