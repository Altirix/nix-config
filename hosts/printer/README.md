# Printers (ROCK 5C / 5C Lite)

`hosts/printer/alluvium` and `hosts/printer/basidium` are Klipper hosts on ROCK 5C Lites (RK3582). With
`homelab.hardware.rock5c.unlocked`, U-Boot only fails what the chip's OTP marks bad, not the
vendor's fixed 2x A76 / no GPU. Usually most of the chip comes back, rarely all of it.

From Armbian with a mainline kernel (nixos-anywhere kexecs with its device tree), install to the
eMMC, building on the board, keeping Armbian's host key (the age key in `.sops.yaml`), then write
U-Boot to the eMMC's raw sectors. Erase an old loader in SPI flash first if `/dev/mtd0` exists,
the board boots SPI before eMMC:

```sh
nix run github:nix-community/nixos-anywhere -- --flake .#alluvium --build-on remote --copy-host-keys root@<ip>
ssh admin@alluvium sudo rock5c-install-uboot /dev/mmcblk0   # the eMMC, check lsblk
```

Add the host key to `.sops.yaml` as in the top-level README.

Rerun `rock5c-install-uboot` after changing `unlocked`. Check what is enabled now and stress the big cores:

```sh
nproc; ls /sys/class/devfreq
stress-ng --cpu 0 --taskset 4-7 --timeout 30m
```

A GPU with one bad core is kept with `homelab.hardware.rock5c.gpuShaderMask`: U-Boot leaves
the GPU enabled and a patched `panthor.ko` (only the module, the kernel stays 6.18) masks the
core out. The fuse bit doesn't say which `shader_present` bit it is, so probe one core at a time
with `gpuShaderMask = "0x1"` deployed (a full G610 MP4 is `0x50005`):

```sh
hexdump -C -s 0x1d -n 3 /sys/bus/nvmem/devices/rockchip-otp0/nvmem   # ip-state, byte 2 & 0x1e = bad GPU core
for m in 0x1 0x4 0x10000 0x40000; do
  modprobe -r panthor; modprobe panthor shader_mask=$m
  glmark2-es2-drm --off-screen --run-forever & sleep 300; kill $!
  dmesg | grep -i -E "panthor.*(fault|timeout|reset)"
done
```

Set `gpuShaderMask` to `0x50005` without the core that faults.

Mainsail is on `http://alluvium.local`. `printer.cfg` only seeds
`/var/lib/moonraker/config/printer.cfg` on first start, edit the live copy from Mainsail.

The on-board AIC8800D80 (USB Wi-Fi 6 / BT 5.4) has no mainline driver, `homelab.hardware.rock5c.wifi`
builds Radxa's out of tree with its firmware. Check with `ip link` and `bluetoothctl list`.
`homelab.wifi.enable` joins the network in `wifi-ssid` / `wifi-psk` of `secrets/printer.yaml`.
