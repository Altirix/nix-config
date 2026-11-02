# What chromebook-install-recovery writes to slot R and its root partition.
{ pkgs, name, kernelImage, rootfsImage }:
pkgs.runCommand name {
  inherit kernelImage rootfsImage;
  nativeBuildInputs = [ pkgs.zstd ];
  # kernel.bin names the recovery system in its command line; the bundle is
  # written raw, so it must not pull the uncompressed closure in beside it.
  __structuredAttrs = true;
  unsafeDiscardReferences.out = true;
} (builtins.readFile ./recovery-bundle.sh)
