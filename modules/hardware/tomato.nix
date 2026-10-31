{ config, lib, pkgs, ... }:

let
  cfg = config.homelab.hardware.tomato;
  tools = pkgs.callPackage ./tomato/tools.nix { };
  buildTools = pkgs.buildPackages.callPackage ./tomato/tools.nix { };
in
{
  options.homelab.hardware.tomato = {
    enable = lib.mkEnableOption "headless Google Tomato (MT8195) with stock Depthcharge";
    wifi = lib.mkEnableOption "Intel AX200 Wi-Fi firmware";
    # See hosts/sbc/tomato.md for the eMMC layout and how the slots fall back.
    kernelSlots = {
      a = lib.mkOption {
        type = lib.types.str;
        default = "/dev/disk/by-partlabel/tomato-kern-a";
        description = "Kernel slot A, alternated with B by nixos-install and nixos-rebuild.";
      };
      b = lib.mkOption {
        type = lib.types.str;
        default = "/dev/disk/by-partlabel/tomato-kern-b";
        description = "Kernel slot B, alternated with A by nixos-install and nixos-rebuild.";
      };
    };
    recovery = {
      kernel = lib.mkOption {
        type = lib.types.str;
        default = "/dev/disk/by-partlabel/tomato-kern-r";
        description = "Recovery kernel slot, booted when A and B both fail. Never written by nixos-rebuild.";
      };
      root = lib.mkOption {
        type = lib.types.str;
        default = "/dev/disk/by-partlabel/tomato-recovery";
        description = "Recovery root filesystem partition.";
      };
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
    # Some RTL8152/8153/8156 USB Ethernet adapters need firmware. Keep only
    # their blobs, rather than the complete firmware collection on the eMMC.
    nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "linux-firmware";
    hardware.firmware = [ (pkgs.runCommand "tomato-ethernet-firmware" { } ''
      mkdir -p $out/lib/firmware
      cp -r ${pkgs.linux-firmware}/lib/firmware/rtl_nic $out/lib/firmware/
    '') ] ++ lib.optional cfg.wifi (pkgs.callPackage ./tomato/ax200-firmware.nix { });
    boot.loader = {
      grub.enable = false;
      systemd-boot.enable = false;
      generic-extlinux-compatible.enable = false;
      efi.canTouchEfiVariables = false;
      external = {
        enable = true;
        installHook = pkgs.writeShellScript "install-tomato-kernel" ''
          exec ${tools.install}/bin/tomato-install-kernel \
            ${tools.pack}/bin/tomato-pack-kernel \
            ${lib.escapeShellArg cfg.kernelSlots.a} ${lib.escapeShellArg cfg.kernelSlots.b} "$@"
        '';
      };
    };

    # A new kernel gets one trial boot. Confirm it once the system, including
    # sshd, is up; otherwise the next reset boots the previous slot.
    systemd.services.tomato-mark-good = {
      description = "Confirm the booted Tomato kernel slot";
      wantedBy = [ "multi-user.target" ];
      after = [ "multi-user.target" "sshd.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${tools.markGood}/bin/tomato-mark-good ${lib.escapeShellArg cfg.kernelSlots.a} ${lib.escapeShellArg cfg.kernelSlots.b}";
      };
    };
    # A trial kernel that panics or hangs must reset for Depthcharge to fall back.
    systemd.settings.Manager.RuntimeWatchdogSec = lib.mkDefault "30s";

    environment.systemPackages = [
      (pkgs.writeShellScriptBin "tomato-install-recovery" ''
        if [ $# != 1 ]; then
          echo 'usage: tomato-install-recovery RECOVERY' >&2
          exit 2
        fi
        exec ${tools.writeRecovery}/bin/tomato-write-recovery \
          ${lib.escapeShellArg cfg.recovery.kernel} ${lib.escapeShellArg cfg.recovery.root} "$1"
      '')
    ];

    hardware.deviceTree = {
      enable = true;
      filter = "mt8195-cherry-tomato-r*.dtb";
    };
    boot.initrd.availableKernelModules = [
      "mtk-sd" "mmc_block"
      "mtu3" "xhci-mtk-hcd" "phy-mtk-tphy" "usb_storage" "uas" "sd_mod"
      # External video is DP Alt Mode over USB-C, including USB-C/HDMI adapters.
      # Include the display pipeline early so tty1 can show initrd diagnostics.
      "mediatek-drm" "mtk_dp" "phy-mtk-dp"
      "cros-ec-typec" "cros-ec-spi"
    ];
    boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty1" "rootwait" "panic=10" ];

    # Build-time image generation is separate from the runtime install hook,
    # avoiding a cycle through the NixOS system closure.
    system.build.tomatoKernel = pkgs.runCommand "tomato-kernel.bin" {
      nativeBuildInputs = [ buildTools.pack ];
    } ''
      tomato-pack-kernel ${config.system.build.toplevel} $out
    '';
  };
}
