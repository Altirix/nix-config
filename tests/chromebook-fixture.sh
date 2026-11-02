# A fake NixOS toplevel: kernel, initrd, command line and three board DTBs.
mkdir -p "$out/dtbs/vendor"
printf 'test ARM64 kernel payload\n' > "$out/kernel"
printf 'test initramfs payload\n' > "$out/initrd"
printf 'root=LABEL=nixos-root rootwait console=ttyS0,115200n8' > "$out/kernel-params"
for rev in 1 2 3; do
  printf '/dts-v1/; / { compatible = "vendor,board-rev%s", "vendor,board"; };\n' "$rev" > board.dts
  dtc -I dts -O dtb board.dts -o "$out/dtbs/vendor/board-r$rev.dtb"
done
