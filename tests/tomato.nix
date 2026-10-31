# Host-side format/boot-contract checks; these do not emulate Tomato hardware.
{ self, pkgs, cross }:
let
  fixtures = import ./tomato-fixture.nix { inherit pkgs; };
  inherit (fixtures) tools kernelImage;
  fixture = fixtures.system;
  installed = self.nixosConfigurations.colluvium.config;
  installer = self.nixosConfigurations.tomato-installer.config;
  recovery = self.nixosConfigurations.tomato-recovery.config;
  earlyModules = pkgs.makeModulesClosure {
    kernel = installed.boot.kernelPackages.kernel.modules;
    rootModules = installed.boot.initrd.availableKernelModules ++ installed.boot.initrd.kernelModules;
    firmware = pkgs.runCommand "empty-tomato-test-firmware" { } "mkdir -p $out";
  };
  rootfsImage = fixtures.rootfs "TOMATO-USB";
  image = import ../modules/hardware/tomato/usb-image.nix { inherit pkgs kernelImage rootfsImage; rootExtraSpaceMiB = 16; };
in
# These builders previously required aarch64-linux on the x86 package output.
assert self.packages.x86_64-linux.tomato-installer-image.system == "x86_64-linux";
assert cross.installed.system.build.toplevel.system == "x86_64-linux";
assert cross.installer.system.build.toplevel.system == "x86_64-linux";
assert cross.installer.hardware.deviceTree.package.system == "x86_64-linux";
assert cross.installer.system.build.tomatoKernel.system == "x86_64-linux";
assert cross.recovery.system.build.tomatoRecovery.system == "x86_64-linux";
assert cross.recovery.nixpkgs.hostPlatform.system == "aarch64-linux";
assert cross.installed.nixpkgs.hostPlatform.system == "aarch64-linux";
assert cross.installer.nixpkgs.hostPlatform.system == "aarch64-linux";
assert !installer.services.xserver.enable;
assert installer.services.getty.autologinUser == "nixos";
assert installer.boot.consoleLogLevel == 7;
assert builtins.elem "console=tty1" installer.boot.kernelParams;
assert builtins.elem "ARCH=arm64" cross.installerPkgs.vboot-utils.makeFlags;
assert builtins.elem "ARCH=arm64" cross.installedPkgs.vboot-utils.makeFlags;
assert !(builtins.elem "ARCH=arm64" cross.installerPkgs.buildPackages.vboot-utils.makeFlags);
assert installed.homelab.wifi.enable;
assert installed.homelab.wifi.secretsFile == ../secrets/sbc.yaml;
assert installed.homelab.hardware.tomato.wifi;
assert installer.homelab.hardware.tomato.wifi;
assert !installed.hardware.enableRedistributableFirmware;
assert !installed.services.klipper.enable;
assert installed.networking.hostName == "colluvium";
assert installed.nixpkgs.hostPlatform.system == "aarch64-linux";
assert !installed.boot.loader.systemd-boot.enable;
assert !installed.boot.loader.grub.enable;
assert !installed.boot.loader.generic-extlinux-compatible.enable;
assert installed.boot.loader.external.enable;
assert installed.fileSystems."/".device == "/dev/disk/by-label/tomato-root";
assert installer.fileSystems."/".device == "/dev/disk/by-label/TOMATO-USB";
assert !installer.services.openssh.settings.PasswordAuthentication;
assert installer.users.users.admin.openssh.authorizedKeys.keyFiles != [ ];
assert installer.environment.etc."tomato-system".source == installed.system.build.toplevel;
assert installer.environment.etc."tomato-recovery".source == recovery.system.build.tomatoRecovery;
assert recovery.fileSystems."/".device == "/dev/disk/by-label/tomato-recovery";
assert recovery.networking.hostName == "tomato-recovery";
assert !recovery.services.openssh.settings.PasswordAuthentication;
# Live systems must never rewrite the eMMC kernel slots.
assert installer.boot.loader.external.installHook != installed.boot.loader.external.installHook;
assert recovery.boot.loader.external.installHook != installed.boot.loader.external.installHook;
assert builtins.elem "multi-user.target" installed.systemd.services.tomato-mark-good.wantedBy;
assert builtins.elem "panic=10" installed.boot.kernelParams;
pkgs.runCommand "tomato-boot-contract" {
  nativeBuildInputs = [ tools.pack tools.install pkgs.vboot-utils pkgs.ubootTools pkgs.dtc pkgs.gptfdisk pkgs.e2fsprogs ];
} ''
  # Resolve early boot modules (including builtins) using the actual ARM64 kernel.
  test -s ${earlyModules}/lib/modules/${installed.boot.kernelPackages.kernel.modDirVersion}/modules.dep
  for rev in 1 2 3; do
    dtb=${installed.boot.kernelPackages.kernel}/dtbs/mediatek/mt8195-cherry-tomato-r$rev.dtb
    fdtget -t s "$dtb" / compatible | grep -F "google,tomato-rev$rev"
  done
  fdtget -t s ${installed.boot.kernelPackages.kernel}/dtbs/mediatek/mt8195-cherry-tomato-r3.dtb / compatible | grep -F 'google,tomato-rev4'

  vbutil_kernel --verify ${kernelImage} \
    --signpubkey ${pkgs.vboot-utils}/share/vboot/devkeys/kernel_subkey.vbpubk
  vbutil_kernel --get-vmlinuz ${kernelImage} --vmlinuz-out kernel.itb
  test "$(fdtget -t s kernel.itb /images/kernel-1 type)" = kernel_noload
  test "$(fdtget -t s kernel.itb /images/kernel-1 arch)" = arm64
  if fdtget kernel.itb /configurations default; then
    echo 'Unexpected fallback DTB' >&2
    exit 1
  fi
  test "$(fdtget -l kernel.itb /configurations | wc -l)" = 3
  # Check the packed initrd and kernel contents, not just the FIT header.
  index=0
  for node in $(fdtget -l kernel.itb /images); do
    type=$(fdtget -t s kernel.itb "/images/$node" type)
    if [ "$type" = ramdisk ]; then
      dumpimage -T flat_dt -p "$index" -o recovered-initrd kernel.itb
      cmp recovered-initrd ${fixture}/initrd
    fi
    index=$((index + 1))
  done
  test -s recovered-initrd
  dumpimage -T flat_dt -p 0 -o recovered-kernel kernel.itb
  cmp recovered-kernel ${fixture}/kernel
  dump_kernel_config ${kernelImage} > cmdline
  grep -F 'kern_guid=%U' cmdline
  grep -F 'init=${fixture}/init' cmdline
  grep -F 'root=LABEL=TOMATO-USB' cmdline

  # Incomplete DTB sets must fail instead of producing a misleading image.
  cp -r ${fixture} incomplete
  chmod -R u+w incomplete
  rm incomplete/dtbs/mediatek/mt8195-cherry-tomato-r2.dtb
  if tomato-pack-kernel incomplete broken.bin; then exit 1; fi
  # The update hook must reject regular files, before any disk write.
  if tomato-install-kernel tomato-pack-kernel ${rootfsImage} ${rootfsImage} ${fixture}; then exit 1; fi

  image=${image}/tomato-installer.img
  sgdisk -v "$image" | tee gpt-check
  grep -F 'No problems found.' gpt-check
  if grep -i corrupt gpt-check; then exit 1; fi
  test "$(cgpt show -i 1 -b "$image")" = 2048
  test "$(cgpt show -i 1 -s "$image")" = 262144
  test "$(cgpt show -i 1 -P "$image")" = 10
  test "$(cgpt show -i 1 -S "$image")" = 1
  test "$(cgpt show -i 1 -t "$image")" = FE3A2A5D-4F32-41A7-B725-ACCC3285A309
  test "$(cgpt show -i 2 -b "$image")" = 264192
  dd if="$image" of=recovered-root bs=512 skip=264192 count=$(cgpt show -i 2 -s "$image") status=none
  test "$(stat -c %s recovered-root)" = $(( $(stat -c %s ${rootfsImage}) + 16 * 1024 * 1024 ))
  e2fsck -fn recovered-root
  debugfs -R 'cat /marker' recovered-root | grep -Fx tomato-root-payload
  mkdir -p $out
  cp gpt-check cmdline $out/
''
