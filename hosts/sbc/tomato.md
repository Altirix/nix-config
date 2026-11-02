# Google Tomato (MT8195)

`colluvium` is the headless Acer Chromebook Spin 513 CP513-2H / Google Tomato
mainboard, keeping stock Google firmware and Depthcharge. The board module is
[`modules/hardware/tomato.nix`](../../modules/hardware/tomato.nix); booting,
installing, updates and recovery are common to all Chromebook boards and covered
in [modules/hardware/chromebook/README.md](../../modules/hardware/chromebook/README.md).

The upstream rev1, rev2 and rev3 DTBs are packed into the FIT; rev3 also covers
rev4. The display is a text console; a graphical desktop, 3D acceleration, audio
and suspend are outside this setup.

## Build the installer

```sh
nix build .#colluvium-installer-image
```

It carries the prebuilt `colluvium` system and `colluvium-recovery`. Write and boot it
as described in the Chromebook README, then check early hardware over SSH:

```sh
cat /proc/device-tree/model; echo
```

```sh
lsblk -o PATH,SIZE,TYPE,TRAN,MOUNTPOINTS
```

```sh
dmesg | grep -Ei 'mmc|xhci|usb|error|fail'
```

The internal disk is the eMMC; check which `/dev/mmcblkN` it is (not
`mmcblkNboot0/1`) before running `chromebook-install`.

## Text console over USB-C/HDMI

A USB-C to HDMI adapter or dock uses Tomato's DisplayPort Alt Mode path. The
initrd includes the MediaTek display controller, DP transmitter/PHY and ChromeOS
EC Type-C/SPI drivers, so a working display can show early boot diagnostics;
`console=tty1` is the primary console. The tested adapter displayed the installer
console; others are untested. A blank display can be a display-path failure while
Linux is running: check the wired DHCP lease and SSH before concluding that boot
failed. `root=fstab` is expected: the initrd mounts the root from `fileSystems."/"`.

## Serial

UART is `ttyS0`, 115200 8N1, kept as `console=ttyS0,115200n8` for debugging. The
pinned device tree's `stdout-path` is `serial0:115200n8`, its `serial0` alias points
to UART0, and the kernel includes the MediaTek 8250 serial driver. Establish the
board connector, pinout and voltage before attaching a serial adapter.

## Wi-Fi and secrets

Colluvium imports `modules/sbc.nix`, which enables `homelab.wifi`: Intel AX200
firmware (`homelab.hardware.tomato.wifi`) and `wifi-ssid` / `wifi-psk` from
`secrets/sbc.yaml` through wpa_supplicant. The live systems use NetworkManager.

`chromebook-install` keeps the installer's Ed25519 SSH host key, so Colluvium's
SOPS recipient can be derived in the installer before installing:

```sh
/etc/chromebook-system/sw/bin/ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
```

Add that public `age1...` recipient to `.sops.yaml` and its `sbc` group, then
re-encrypt with an existing authorized identity:

```sh
sops updatekeys secrets/sbc.yaml
```

The installer always ships the SOPS-enabled Colluvium system. Until the key is
authorized, the first installation boots with wired networking but secret
decryption fails during activation and Wi-Fi stays down. After authorizing it,
update with `nixos-rebuild`, or rebuild the installer to get a system that
decrypts on first boot.

## Validation

```sh
nix build .#checks.x86_64-linux.tomato
```

This checks the Tomato and Colluvium configuration (cross-build platforms, DTB list,
consoles, mark-good, live systems that never touch the kernel slots), that the
pinned kernel ships every packed DTB with the right compatibles, and that the early
storage/USB/display modules resolve. The shared Chromebook checks cover the boot
formats and slots.

USB boot and the USB-C/HDMI text console have been verified on hardware with an
earlier installer image. The complete cross-compiled image, SSH access, AX200
Wi-Fi, eMMC installation, recovery, slot fallback and rebooting from eMMC still
need validation on the board.
