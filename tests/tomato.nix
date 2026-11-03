# Tomato board and Colluvium configuration contracts, plus the real pinned DTBs and
# early module closure. The boot formats are covered by chromebook.nix.
{ self, pkgs, cross }:
let
  layout = import ../modules/hardware/chromebook/layout.nix;
  installed = self.nixosConfigurations.colluvium.config;
  installer = self.nixosConfigurations.colluvium-installer.config;
  recovery = self.nixosConfigurations.colluvium-recovery.config;
  kernel = installed.boot.kernelPackages.kernel;
  markGood = installed.systemd.services.chromebook-mark-good;
in
# These builders previously required aarch64-linux on the x86 package output.
assert self.packages.x86_64-linux.colluvium-installer-image.system == "x86_64-linux";
assert cross.installed.config.system.build.toplevel.system == "x86_64-linux";
assert cross.installer.config.system.build.toplevel.system == "x86_64-linux";
assert cross.installer.config.hardware.deviceTree.package.system == "x86_64-linux";
assert cross.installer.config.system.build.chromebookKernel.system == "x86_64-linux";
assert cross.recovery.config.system.build.chromebookRecovery.system == "x86_64-linux";
assert cross.recovery.config.nixpkgs.hostPlatform.system == "aarch64-linux";
assert cross.installed.config.nixpkgs.hostPlatform.system == "aarch64-linux";
assert cross.installer.config.nixpkgs.hostPlatform.system == "aarch64-linux";
assert builtins.elem "ARCH=arm64" cross.installer.pkgs.vboot-utils.makeFlags;
assert builtins.elem "ARCH=arm64" cross.installed.pkgs.vboot-utils.makeFlags;
assert !(builtins.elem "ARCH=arm64" cross.installer.pkgs.buildPackages.vboot-utils.makeFlags);

assert installed.homelab.hardware.chromebook.board == "tomato";
assert installed.homelab.hardware.chromebook.dtbs == installer.homelab.hardware.chromebook.dtbs;
assert installed.homelab.wifi.enable;
assert installed.homelab.wifi.secretsFile == ../secrets/sbc.yaml;
assert installed.homelab.hardware.tomato.wifi;
assert installer.homelab.hardware.tomato.wifi;
assert !installed.hardware.enableRedistributableFirmware;
assert !installed.services.klipper.enable;
assert installed.networking.hostName == "colluvium";
assert !installed.boot.loader.systemd-boot.enable;
assert !installed.boot.loader.grub.enable;
assert !installed.boot.loader.generic-extlinux-compatible.enable;
assert installed.boot.loader.external.enable;
assert installed.fileSystems."/".device == "/dev/disk/by-label/${layout.root}";
# The display is the primary console, serial is kept for debugging.
assert pkgs.lib.last (builtins.filter (pkgs.lib.hasPrefix "console=") installed.boot.kernelParams) == "console=tty1";
assert builtins.elem "panic=10" installed.boot.kernelParams;
assert map (o: o.name) installed.hardware.deviceTree.overlays == [ "tomato-radio-kill" ];
assert map (o: o.name) installer.hardware.deviceTree.overlays == [ "tomato-radio-kill" ];
assert markGood.enable && builtins.elem "sshd.service" markGood.requires;

assert !installer.services.xserver.enable;
assert installer.services.getty.autologinUser == "nixos";
assert installer.boot.consoleLogLevel == 7;
assert installer.fileSystems."/".device == "/dev/disk/by-label/${layout.usbRoot}";
assert recovery.fileSystems."/".device == "/dev/disk/by-label/${layout.recovery}";
assert recovery.networking.hostName == "colluvium-recovery";
assert !installer.services.openssh.settings.PasswordAuthentication;
assert !recovery.services.openssh.settings.PasswordAuthentication;
assert installer.users.users.admin.openssh.authorizedKeys.keyFiles != [ ];
assert installer.environment.etc."chromebook-system".source == installed.system.build.toplevel;
assert installer.environment.etc."chromebook-recovery".source == recovery.system.build.chromebookRecovery;
# Live systems must never rewrite the internal kernel slots, or confirm them.
assert installer.boot.loader.external.installHook.name == "chromebook-live-no-install";
assert recovery.boot.loader.external.installHook.name == "chromebook-live-no-install";
assert !installer.systemd.services.chromebook-mark-good.enable;
assert !recovery.systemd.services.chromebook-mark-good.enable;
pkgs.runCommand "tomato-board" {
  inherit kernel;
  inherit (kernel) modDirVersion;
  radioKill = ../modules/hardware/tomato/radio-kill.dtso;
  earlyModules = pkgs.makeModulesClosure {
    kernel = kernel.modules;
    rootModules = installed.boot.initrd.availableKernelModules ++ installed.boot.initrd.kernelModules;
    firmware = pkgs.runCommand "empty-firmware" { } "mkdir -p $out";
  };
  nativeBuildInputs = [ pkgs.dtc ];
} (builtins.readFile ./tomato-board.sh)
