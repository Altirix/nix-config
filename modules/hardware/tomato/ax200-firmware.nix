{ lib, runCommand, linux-firmware }:

# AX200 uses the in-tree iwlwifi driver. Dereference linux-firmware's aliases
# so the selected blobs remain usable without the rest of its firmware tree.
runCommand "ax200-firmware" {
  meta.license = lib.licenses.unfreeRedistributableFirmware;
} ''
  mkdir -p $out/lib/firmware
  cp -L ${linux-firmware}/lib/firmware/iwlwifi-cc-a0-*.ucode $out/lib/firmware/
''
