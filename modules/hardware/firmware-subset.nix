# A few blobs out of linux-firmware instead of the whole collection. `paths` are
# relative to lib/firmware and may be globs. Symlinks are dereferenced so the blobs
# stay usable without the rest of the tree.
{ pkgs }:
name: paths:
pkgs.runCommand name { meta.license = pkgs.lib.licenses.unfreeRedistributableFirmware; } ''
  cd ${pkgs.linux-firmware}/lib/firmware
  for path in ${toString paths}; do
    mkdir -p "$out/lib/firmware/$(dirname "$path")"
    cp -rL "$path" "$out/lib/firmware/$(dirname "$path")/"
  done
''
