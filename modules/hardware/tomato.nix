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
    kernelPartition = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/by-partlabel/tomato-kernel";
      description = "Raw ChromeOS kernel partition updated by nixos-install and nixos-rebuild.";
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
            ${lib.escapeShellArg cfg.kernelPartition} "$@"
        '';
      };
    };

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
    boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty1" "rootwait" ];

    # Build-time image generation is separate from the runtime install hook,
    # avoiding a cycle through the NixOS system closure.
    system.build.tomatoKernel = pkgs.runCommand "tomato-kernel.bin" {
      nativeBuildInputs = [ buildTools.pack ];
    } ''
      tomato-pack-kernel ${config.system.build.toplevel} $out
    '';
  };
}
