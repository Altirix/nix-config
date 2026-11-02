{ config, lib, pkgs, ... }:

# Headless ARM64 Chromebooks booting NixOS from stock firmware and Depthcharge:
# signed kernel slots A/B plus recovery (R), see README.md. A board module (e.g.
# ../tomato.nix) enables this and supplies its DTBs, drivers and console.
let
  cfg = config.homelab.hardware.chromebook;
  layout = import ./layout.nix;
  tools = pkgs.callPackage ./tools.nix { inherit (cfg) dtbs; };
  buildTools = pkgs.buildPackages.callPackage ./tools.nix { inherit (cfg) dtbs; };
in
{
  options.homelab.hardware.chromebook = {
    enable = lib.mkEnableOption "booting NixOS from stock Chromebook firmware (Depthcharge)";
    board = lib.mkOption {
      type = lib.types.str;
      example = "tomato";
      description = "The board module, modules/hardware/<board>.nix, which the installer and recovery systems also use.";
    };
    dtbs = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.str;
      example = [ "mediatek/mt8195-cherry-tomato-r1.dtb" ];
      description = "Board device trees, relative to the kernel's dtbs/, all packed into the signed FIT.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;
    # Vboot selects crossystem's platform backend using ARCH, not HOST_ARCH.
    # Without this, cross-building on x86 produces an ARM binary using ACPI.
    nixpkgs.overlays = [ (final: prev: {
      vboot-utils = prev.vboot-utils.overrideAttrs (old: {
        makeFlags = old.makeFlags
          ++ lib.optional final.stdenv.hostPlatform.isAarch64 "ARCH=arm64";
      });
    }) ];
    # Headless installs use USB Ethernet; some RTL8152/8153/8156 adapters need
    # firmware. Keep only their blobs, not the complete firmware collection.
    nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "linux-firmware";
    hardware.firmware = [ (import ../firmware-subset.nix { inherit pkgs; } "usb-ethernet-firmware" [ "rtl_nic" ]) ];

    boot.loader = {
      grub.enable = false;
      systemd-boot.enable = false;
      generic-extlinux-compatible.enable = false;
      efi.canTouchEfiVariables = false;
      external = {
        enable = true;
        installHook = "${tools.install}/bin/chromebook-install-kernel";
      };
    };
    hardware.deviceTree.enable = true;
    boot.initrd.availableKernelModules = [ "mmc_block" "usb_storage" "uas" "sd_mod" ];
    # A trial kernel that panics or hangs must reset for Depthcharge to fall back.
    boot.kernelParams = [ "rootwait" "panic=10" ];
    systemd.settings.Manager.RuntimeWatchdogSec = lib.mkDefault "30s";

    fileSystems."/" = lib.mkDefault {
      device = "/dev/disk/by-label/${layout.root}";
      fsType = "ext4";
    };

    # A new kernel gets one trial boot. Confirm it only once sshd is running and
    # there is a default route; otherwise the next reset boots the previous slot.
    systemd.services.chromebook-mark-good = {
      description = "Confirm the booted Chromebook kernel slot";
      wantedBy = [ "multi-user.target" ];
      requires = [ "sshd.service" ];
      wants = [ "network-online.target" ];
      after = [ "multi-user.target" "sshd.service" "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = "${tools.waitOnline}/bin/chromebook-wait-online";
        ExecStart = "${tools.markGood}/bin/chromebook-mark-good";
      };
    };

    environment.systemPackages = [ tools.installRecovery ];
    system.build.chromebookTools = tools;

    # Built separately from the install hook, avoiding a cycle through the system closure.
    system.build.chromebookKernel = pkgs.runCommand "chromebook-kernel.bin" {
      nativeBuildInputs = [ buildTools.pack ];
    } ''
      chromebook-pack-kernel ${config.system.build.toplevel} $out
    '';
  };
}
