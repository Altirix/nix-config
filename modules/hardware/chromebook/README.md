# Chromebooks (stock firmware, Depthcharge)

Headless ARM64 Chromebooks keep Google's firmware and boot NixOS through
Depthcharge's developer mode. There is no ESP, GRUB or systemd-boot: Depthcharge
reads a signed FIT (kernel, initrd, board DTBs) straight from raw ChromeOS kernel
partitions.

| File | Role |
|---|---|
| `default.nix` | `homelab.hardware.chromebook`: boot hook, kernel slots, mark-good, watchdog, root filesystem |
| `layout.nix` | partition labels and sizes, the single source for module, scripts and tests |
| `tools.nix` | the scripts below, with the layout and the board's DTB list substituted |
| `pack-kernel.sh` | signs a NixOS generation into a Depthcharge kernel image |
| `install-kernel.sh`, `mark-good.sh`, `wait-online.sh` | A/B updates and confirming a boot |
| `partition.sh`, `write-recovery.sh` | first-install layout and the recovery slot |
| `usb-image.nix`, `recovery-bundle.nix` | the USB installer image and the recovery payload |
| `../../../installers/chromebook/` | the live systems: USB installer and recovery |

A board module enables `homelab.hardware.chromebook` and supplies its DTBs,
early drivers and consoles. See [`../tomato.nix`](../tomato.nix) and
[hosts/sbc/tomato.md](../../../hosts/sbc/tomato.md).

## Firmware

Developer Mode must already be enabled. From a privileged ChromeOS shell, enable
external developer boot:

```sh
crossystem dev_boot_usb=1
```

Keep the stock firmware: nothing here writes SPI firmware or the EC. The images
use Chromium's **public developer signing keys** and need developer boot; they
do not establish production verified boot. USB boot normally needs Ctrl+U at the
developer screen, so a bare board needs a temporary keyboard and display (SSH
cannot select USB before Linux starts). Once installed, the firmware must boot the
internal disk by default. Do not disable Developer Mode after installation.

## Internal disk layout

| # | Partition label | Size | Contents |
|---|---|---|---|
| 1 | `nixos-kern-a` | 128 MiB | kernel slot A |
| 2 | `nixos-kern-b` | 128 MiB | kernel slot B |
| 3 | `nixos-kern-r` | 128 MiB | recovery kernel (R) |
| 4 | `nixos-recovery` | 4 GiB | recovery root, ext4 label `nixos-recovery` |
| 5 | `nixos-root` | rest | NixOS root, ext4 label `nixos-root` |

The USB installer's root is `NIXOS-CB-USB`, so neither it nor recovery can stand
in for the installed root. Do not attach another disk using these labels.

## How boots fall back

Depthcharge boots the highest-priority kernel partition that is confirmed
(`successful`) or still has tries left, and skips an unconfirmed slot whose
tries reach zero:

| Priority | Slot |
|---|---|
| 3 | the newly written kernel, one trial boot (`tries=1`, `successful=0`) |
| 2 | the previously booted, confirmed kernel |
| 1 | recovery, always confirmed; never written by `nixos-rebuild` |

Each `nixos-install`/`nixos-rebuild` writes the slot that is **not** running
(slot A when booted from USB or recovery, demoting B so the new kernel is tried
first). `chromebook-mark-good.service` confirms the booted slot once sshd is
running and there is a default route. A new kernel that panics (`panic=10`),
hangs userspace (systemd's 30 s hardware watchdog), or boots without sshd or a
network is not confirmed, and the next reset boots the previous slot with the
previous generation's `init=`. If A and B both fail, the firmware boots recovery.
A kernel that hangs before systemd starts its watchdog needs a power cycle.

Updates are refused while the booted slot is unconfirmed, so the only known-good
slot is never overwritten. Payloads are size-checked before any slot is
invalidated. There is no generation menu: A/B keeps the current and previous
generations, and recovery can reinstall any generation.

## Build and write the USB installer

From an x86_64 Linux machine (cross-compiled) or an ARM64 one (native):

```sh
nix build .#<host>-installer-image
```

The first cross-build may compile dependencies that are not in the binary cache.
In a Git checkout, add new files to Git first (flakes omit untracked files).

`result/installer.img` is a GPT disk with a signed kernel partition and a writable
ext4 root. It carries the host's prebuilt system, the recovery bundle and a source
snapshot, so the first installation works offline. It reserves 1 GiB of free space
but does not grow to fill the stick; check `ls -lh result/installer.img` and use a
stick with room to spare.

**Writing erases the USB device.** Check it with `lsblk`, unmount its partitions
and write the whole disk:

```sh
sudo dd if=result/installer.img of=/dev/sdX bs=4M conv=fsync status=progress
```

Boot it through external developer boot. Use a USB Ethernet adapter and wired DHCP
(Realtek adapter firmware is included). The installer autologins as `nixos` on the
display console and accepts the repository's admin SSH keys as `admin`, with
passwordless sudo:

```sh
ssh admin@<installer-ip>
```

## Install

**This erases ChromeOS and everything on the selected disk.** Have a ChromeOS
recovery path first. Check the internal disk with `lsblk`; the example uses
`/dev/mmcblk0`. `chromebook-partition` refuses USB and SD media, eMMC boot/RPMB
areas, partitions and the disk holding the running root, and `chromebook-install`
asks for confirmation:

```sh
sudo chromebook-install /dev/mmcblk0
```

It partitions the disk, writes the recovery kernel and root, creates the NixOS
root with a copy of the flake in `/etc/nixos` (no Git metadata), keeps the
installer's SSH host key, and runs `nixos-install`, whose hook writes slot A on
its trial boot. Power off, remove the USB stick, boot the internal disk and check
that the slot was confirmed:

```sh
ssh admin@<host-ip> systemctl status chromebook-mark-good
```

```sh
ssh admin@<host-ip> sudo cgpt show /dev/mmcblk0
```

## Updates and rollback

From a repository checkout on an ARM64 builder:

```sh
nixos-rebuild switch --flake .#<host> --target-host admin@<host-ip> --sudo
```

`switch` activates the new generation immediately, but its kernel is only tried on
the next reboot. Reboot to confirm it:

```sh
ssh admin@<host-ip> sudo systemctl reboot
```

After a fallback, `cgpt show` lists the failed slot with priority 3, `tries=0` and
`successful=0`; the next update overwrites it.

## Recovery

Recovery is a separate NixOS system (`nixosConfigurations.<host>-recovery`) on
its own root partition, so a broken NixOS root does not affect it. It has the
installer's tools, wired DHCP and key-only SSH as `admin`. It generates its own SSH
host key on first boot (expect a host-key warning) and cannot decrypt the host's
SOPS secrets.

Reinstall a known generation's kernel into slot A (replace `N`):

```sh
sudo mount /dev/disk/by-label/nixos-root /mnt
```

```sh
ls -l /mnt/nix/var/nix/profiles/
```

```sh
sudo nixos-enter --root /mnt -- /nix/var/nix/profiles/system-N-link/bin/switch-to-configuration boot
```

Or push a new build from the builder. Writing the mounted store needs root, so
stream the closure through `sudo`, then install it:

```sh
nix build .#nixosConfigurations.<host>.config.system.build.toplevel
```

```sh
nix-store --export $(nix-store -qR ./result) | ssh admin@<recovery-ip> sudo nix-store --store /mnt --import
```

```sh
ssh admin@<recovery-ip> sudo nixos-enter --root /mnt -- nix-env -p /nix/var/nix/profiles/system --set "$(readlink -f result)"
```

```sh
ssh admin@<recovery-ip> sudo nixos-enter --root /mnt -- /nix/var/nix/profiles/system/bin/switch-to-configuration boot
```

To refresh recovery itself, install it from the running host (not from recovery,
whose root is mounted):

```sh
nix build .#packages.aarch64-linux.<host>-recovery
```

```sh
nix copy --to ssh://admin@<host-ip> ./result
```

```sh
ssh admin@<host-ip> sudo chromebook-install-recovery "$(readlink -f result)"
```

Keep the installer USB for when recovery fails too.

## Adding a board

1. Write `modules/hardware/<board>.nix`: import `./chromebook`, enable
   `homelab.hardware.chromebook` with `board = "<board>"` and the board's `dtbs`,
   and add its device-tree filter, early drivers, consoles and firmware. Import it
   in `modules/default.nix`.
2. Add a host that enables the board (the root filesystem comes from this module).
   `installers/chromebook` finds every host with `homelab.hardware.chromebook`
   enabled and builds `<host>-installer`, `<host>-recovery` and
   `<host>-installer-image`, using the host's settings for its board.

## Validation

```sh
nix build .#checks.x86_64-linux.chromebook
```

```sh
nix build .#checks.x86_64-linux.chromebook-slots
```

`chromebook` checks the formats with a fake board: developer-key signatures, the
packed FIT (kernel, initrd, every DTB, no fallback configuration), the kernel
command line, refusal of missing DTBs and of updates without the internal layout,
the USB image's GPT and payloads, and that the recovery bundle keeps no store
references. `chromebook-slots` (a VM test, which needs KVM) partitions a virtual
disk with `chromebook-partition` and checks the A/B/R flags across install,
confirm, update and install-from-recovery, the refusals and the written payloads,
with Depthcharge's `kern_guid` faked through `CHROMEBOOK_CMDLINE`. Neither emulates
Depthcharge: firmware fallback and the hardware watchdog need a real board.
