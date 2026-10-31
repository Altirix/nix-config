# Google Tomato (MT8195)

`colluvium` is the headless Acer Chromebook Spin 513 CP513-2H / Google Tomato mainboard, retaining stock
Google firmware and Depthcharge. The upstream rev1, rev2 and rev3 DTBs are packaged
in the FIT; rev3 also covers rev4. A USB installer has booted on the physical board
with a text console over USB-C/HDMI. eMMC installation and AX200 Wi-Fi remain
unverified. The display is used for a text
console; a graphical desktop, 3D acceleration, audio and suspend are outside this setup. Use a supported USB Ethernet adapter and wired DHCP
for the first boot (Realtek USB Ethernet firmware is included); the installer and installed host accept the repository's admin
SSH keys (`modules/system/keys/admin/*.pub`) as `admin`, with passwordless sudo.

## Firmware and headless boot

Developer Mode must already be enabled. From a privileged ChromeOS shell, enable
external developer boot with `crossystem dev_boot_usb=1`. Keep the stock firmware;
neither this installer nor the install procedure writes SPI firmware or the EC.
These images use Chromium's **public developer signing keys** and require developer
boot; they do not establish production verified boot.

USB boot normally requires Ctrl+U at the developer screen. A bare board therefore
needs a temporary keyboard/display or an already configured firmware/EC method of
selecting external boot. SSH cannot select USB before Linux starts. Once installed,
select internal-disk boot in the firmware; it must not still default to USB. Do not
disable Developer Mode after installation. UART is `ttyS0`, 115200 8N1; establish the
board connector/pinout and voltage before attaching a serial adapter.

## Text console over USB-C/HDMI

A USB-C to HDMI adapter or dock uses Tomato's DisplayPort Alt Mode path. The
initrd includes the MediaTek display controller, DP transmitter/PHY and ChromeOS
EC Type-C/SPI drivers, so a working display can show early boot diagnostics.
`console=tty1` selects the display console. The USB installer has verbose kernel
messages and autologins as `nixos` at its console, with passwordless sudo and no
X server or desktop. SSH remains key-only as `admin`.

The pinned device tree's `stdout-path` is `serial0:115200n8` and its `serial0`
alias points to UART0; the kernel includes the MediaTek 8250 serial driver. The
existing `console=ttyS0,115200n8` is retained for serial debugging. This does not
establish an external connector pinout or voltage.

The tested USB-C/HDMI adapter displayed the installer console. Other adapters
remain untested. A blank display can be a display-path failure while Linux is running; check its wired DHCP lease
and SSH before concluding that USB boot failed. `root=fstab` is expected: the
initrd mounts the USB root specified by `fileSystems."/"` (`TOMATO-USB`).

## Build and write the USB installer

From an **x86_64 Linux machine with Nix**, cross-compile the installer:

```sh
nix build .#tomato-installer-image
```

The x86 target builds both the ARM64 installer and its offline Colluvium system
with an x86-to-ARM64 toolchain. Kernel signing, filesystem creation and image
assembly use x86 tools. The first cross-build may compile dependencies whose
cross-compiled outputs are not in the binary cache.

On a native ARM64 Nix machine, the same command selects the native ARM64 output.
The explicit package outputs are `packages.x86_64-linux.tomato-installer-image`
and `packages.aarch64-linux.tomato-installer-image` respectively.

If using a Git checkout, add the new files to Git before building (flakes omit
untracked files). The output is `result/tomato-installer.img`: a GPT disk with a
128 MiB ChromeOS kernel partition containing the signed kernel/initrd/FIT and an
ext4 installer root. The image includes the `colluvium` system closure, the
recovery system (`/etc/tomato-recovery`) and a source snapshot, so the first eMMC
installation can be offline. The USB root is writable
and persistent; use a stick large enough for the image. It does not expand to fill
the stick automatically. It reserves an extra 1 GiB of filesystem space and
inodes for first-boot activation and interactive use. Check the image size with
`ls -lh result/tomato-installer.img` and use a stick with room to spare (8 GB or larger).

**Writing erases the selected USB device.** Identify it using `lsblk` and unmount
its mounted partitions first. Write to the whole disk, not a partition:

```sh
sudo dd if=result/tomato-installer.img of=/dev/sdX bs=4M conv=fsync status=progress
```

Insert it, boot through Depthcharge's external developer boot, find the wired DHCP
lease, and connect with `ssh admin@<installer-ip>`. Use your own admin private key;
no private key or Wi-Fi credential is embedded in the image. Check early hardware:

```sh
cat /proc/device-tree/model; echo
lsblk -o PATH,SIZE,TYPE,TRAN,MOUNTPOINTS
ip -br address
dmesg | grep -Ei 'mmc|xhci|usb|error|fail'
```

## SBC Wi-Fi secrets

Colluvium imports `modules/sbc.nix`, which enables `homelab.wifi` by default. The installed
system selects Intel AX200 firmware through `homelab.hardware.tomato.wifi` and
uses `wifi-ssid` / `wifi-psk` from `secrets/sbc.yaml` through wpa_supplicant.
The installer continues to use NetworkManager; these settings apply to the
installed host.

Before deploying this configuration, add Colluvium's real public age recipient
to `.sops.yaml` and its `sbc` group, then run `sops updatekeys secrets/sbc.yaml`
using an existing authorized identity. Edit values with `sops secrets/sbc.yaml`.
Renaming the encrypted file alone does not authorize a new host to decrypt it.

For a first installation, preserve the installer's Ed25519 SSH host key on the
eMMC. Derive its public age recipient in the installer with:

```sh
/etc/tomato-system/sw/bin/ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub
```

Only the public `age1...` recipient belongs in `.sops.yaml`; keep the private
SSH key on the board. The copy steps below preserve that key during installation.
The USB image always ships the SOPS-enabled Colluvium system. Until this key is
authorized, the first installation boots with wired networking but secret
decryption fails during activation and Wi-Fi stays down. After authorizing the
key, update the installed host with `nixos-rebuild` (below), or rebuild the
installer image to get a prebuilt system that decrypts on first boot.

## eMMC layout and boot slots

| # | Partition label | Size | Contents |
|---|---|---|---|
| 1 | `tomato-kern-a` | 128 MiB | kernel slot A |
| 2 | `tomato-kern-b` | 128 MiB | kernel slot B |
| 3 | `tomato-kern-r` | 128 MiB | recovery kernel (R) |
| 4 | `tomato-recovery` | 4 GiB | recovery root, ext4 label `tomato-recovery` |
| 5 | `tomato-root` | rest | Colluvium root, ext4 label `tomato-root` |

Depthcharge boots the highest-priority ChromeOS kernel partition that is either
confirmed (`successful`) or still has tries left, and gives up on an unconfirmed
slot once its tries reach zero:

| Priority | Slot |
|---|---|
| 3 | the newly written kernel, one trial boot (`tries=1`, `successful=0`) |
| 2 | the previously booted, confirmed kernel |
| 1 | recovery, always confirmed; never written by `nixos-rebuild` |

Each `nixos-install`/`nixos-rebuild` writes the slot that is **not** running
(slot A when booted from USB or recovery), so the running kernel remains the
fallback. `tomato-mark-good.service` confirms the booted slot after
`multi-user.target` and sshd are up. A new kernel that panics (`panic=10`), hangs
userspace (systemd's 30 s hardware watchdog) or never reaches that service is
not confirmed, and the next reset boots the previous slot, which carries the
previous generation's `init=`. If A and B both fail, the firmware boots recovery.
A kernel that hangs before systemd starts its watchdog needs a power cycle to fall back.

The hook refuses to update while the booted slot is still unconfirmed, so the only
known-good slot is never overwritten; wait for `tomato-mark-good.service` and retry.
There is no generation menu: A/B gives the current and previous generations, and
recovery can reinstall any generation (below).

## Install to eMMC

**This erases ChromeOS and all data on the selected eMMC.** Back up anything needed
and have a ChromeOS recovery path before doing this. Do not target the USB stick,
an SD card, or `mmcblk*boot0`/`mmcblk*boot1`. The following example uses
`/dev/mmcblk0`; verify the actual device with `lsblk`, its size and the MMC type.
The guard also refuses the disk hosting the running installer root.

Run these from the USB installer:

```sh
set -e
disk=/dev/mmcblk0 # replace only after checking the hardware above
name=${disk##*/}
test "$(cat /sys/class/block/$name/device/type)" = MMC
test "$(lsblk -nro PKNAME "$(findmnt -nro SOURCE /)")" != "$name"

sudo sgdisk --zap-all \
  --new=1:2048:+128M --typecode=1:7F00 --change-name=1:tomato-kern-a \
  --new=2:0:+128M --typecode=2:7F00 --change-name=2:tomato-kern-b \
  --new=3:0:+128M --typecode=3:7F00 --change-name=3:tomato-kern-r \
  --new=4:0:+4G --typecode=4:8300 --change-name=4:tomato-recovery \
  --new=5:0:0 --typecode=5:8300 --change-name=5:tomato-root "$disk"
sudo partprobe "$disk"
sudo udevadm settle
sudo tomato-install-recovery /etc/tomato-recovery
sudo mkfs.ext4 -L tomato-root "${disk}p5"
sudo mount "${disk}p5" /mnt
sudo mkdir -p /mnt/etc/nixos
sudo cp -r /etc/tomato-flake/. /mnt/etc/nixos/
sudo chmod -R u+w /mnt/etc/nixos
sudo mkdir -p /mnt/etc/ssh
sudo cp /etc/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key.pub /mnt/etc/ssh/
sudo chmod 600 /mnt/etc/ssh/ssh_host_ed25519_key
sudo nixos-install --root /mnt --system "$(readlink -f /etc/tomato-system)" \
  --no-channel-copy --no-root-password
sudo sync
sudo umount /mnt
sudo poweroff
```

`tomato-install-recovery` writes the recovery kernel to `tomato-kern-r` (priority 1,
confirmed) and the recovery root to `tomato-recovery`, grown to fill it. The
`nixos-install` hook writes Colluvium's signed kernel to slot A on its trial boot;
slot B stays empty until the first update. There is no ESP, GRUB or systemd-boot.
Remove the USB and boot the internal disk; SSH as `admin` to its DHCP address and
check that the slot was confirmed:

```sh
systemctl status tomato-mark-good
sudo cgpt show /dev/mmcblk0
```

The source snapshot in `/etc/nixos` has no Git metadata; clone your repository
separately when you want to work in a Git checkout.

## Updates and rollback

From a repository checkout on an ARM64 builder:

```sh
nixos-rebuild switch --flake .#colluvium --target-host admin@<colluvium-ip> --sudo
```

`nixos-rebuild` repacks the selected generation's matching kernel, initrd, DTBs and
`init=` path into the inactive slot. The hook checks partition types, disk and
capacity before writing, and invalidates the slot until the write completes.
`switch` activates the new generation immediately, but the new kernel is only
tried on the next reboot; reboot to confirm it:

```sh
ssh admin@<colluvium-ip> sudo systemctl reboot
```

After a fallback, `cgpt show` lists the failed slot with priority 3, `tries=0` and
`successful=0`; the next update overwrites it.

## Recovery

Recovery is a separate NixOS system (`nixosConfigurations.tomato-recovery`) with its
own root partition, so a broken Colluvium root does not affect it. It has the
installer's tools, a text console, wired DHCP and key-only SSH as `admin`. It
generates its own SSH host key on first boot, so expect a host-key warning. It does
not have Colluvium's key and cannot decrypt SOPS secrets.

Reinstall a known generation's kernel into slot A from recovery (replace `N` with
the generation number):

```sh
sudo mount /dev/disk/by-label/tomato-root /mnt
ls -l /mnt/nix/var/nix/profiles/
sudo nixos-enter --root /mnt -- /nix/var/nix/profiles/system-N-link/bin/switch-to-configuration boot
```

Or push a new build from the builder. Writing the eMMC store needs root, so stream
the closure through `sudo` onto the mounted eMMC root, then install it in recovery:

```sh
nix build .#nixosConfigurations.colluvium.config.system.build.toplevel
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

To refresh recovery itself, build it and install it from the running Colluvium
system (not from recovery, whose root is mounted):

```sh
nix build .#packages.aarch64-linux.tomato-recovery
```

```sh
nix copy --to ssh://admin@<colluvium-ip> ./result
```

```sh
ssh admin@<colluvium-ip> sudo tomato-install-recovery "$(readlink -f result)"
```

The installer filesystem label (`TOMATO-USB`), the recovery root (`tomato-recovery`)
and the eMMC root (`tomato-root`) differ, so neither a connected installer nor
recovery can become the installed root. Do not attach another disk using the same
eMMC partition/root labels during updates. Keep the installer USB for when
recovery fails too.

## Validation

```sh
nix build .#checks.x86_64-linux.tomato
```

```sh
nix build .#checks.x86_64-linux.tomato-slots
```

This host-side test verifies the configuration contracts, real pinned Tomato DTBs
and early storage/USB module closure, developer-key signatures, packed kernel and
initrd contents, kernel command line, GPT layout and partition payloads. It also
checks rejection of missing DTBs and non-block install destinations. The
`tomato-slots` VM test partitions a virtual disk with the eMMC layout and checks
the A/B/R priority, tries and successful flags across install, confirm and update,
the refusals (unconfirmed slot, non-kernel partitions, mounted or oversized
recovery root) and the written payloads. Depthcharge's `kern_guid` is faked through
`TOMATO_CMDLINE`. Neither test boots a Tomato board, and Depthcharge's
fallback behaviour and the hardware watchdog are untested. USB boot and the USB-C/HDMI text console have been verified
on hardware with an earlier installer image. The complete cross-compiled image,
SSH access, AX200 Wi-Fi, eMMC installation, recovery, slot fallback and
rebooting from eMMC still need validation on the board.
