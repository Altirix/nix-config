# GPT USB image: the signed kernel partition and the ext4 installer root.
{ pkgs, name, kernelImage, rootfsImage, rootExtraSpaceMiB ? 1024 }:
pkgs.runCommand name {
  inherit kernelImage rootfsImage;
  rootExtraSpaceMiB = toString rootExtraSpaceMiB;
  nativeBuildInputs = [ pkgs.coreutils pkgs.vboot-utils pkgs.e2fsprogs ];
} (builtins.readFile ./usb-image.sh)
