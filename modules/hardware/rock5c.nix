{ config, lib, pkgs, ... }:

# Radxa ROCK 5C / 5C Lite. The Lite is an RK3582: an RK3588S with blocks marked bad in OTP
# (ip-state). U-Boot fails those nodes in the device tree it hands the kernel.
#
# rock5c/patches/ are from Armbian (armbian/build patch/u-boot/v2026.01/board_radxa-e52c, 17853b9):
# - uboot-rk3582-support.patch: RK3582 ip-state fixup, plus the vendor policy of always
#   failing two big cores, the GPU and one rkvdec/rkvenc core.
# - uboot-rk3582-unlock.patch: drops that policy, only blocks this chip's OTP marks bad are
#   failed. Usually that is a big core, a GPU core or an encoder, not nothing: most of the
#   chip comes back, rarely all of it. One bad GPU core still fails the whole GPU.
# Both are no-ops on an RK3588S (5C non-Lite). What survived: `nproc`, `ls /sys/class/devfreq`.
#
# `gpuShaderMask` keeps a GPU with a bad core: uboot-rk3582-keep-gpu.patch leaves the gpu node
# enabled and panthor-shader-mask.patch (panthor.ko only) drops the bad core from shader_present.
#
# `wifi` is the on-board AIC8800D80 on USB, no mainline driver: aic8800.nix builds Radxa's.
let
  cfg = config.homelab.hardware.rock5c;

  # U-Boot needs the DDR init blob from rkbin, it is the only unfree package let through.
  uboot = pkgs.buildUBoot {
    defconfig = "rock-5c-rk3588s_defconfig";
    extraPatches = [ ./rock5c/patches/uboot-rk3582-support.patch ]
      ++ lib.optional cfg.unlocked ./rock5c/patches/uboot-rk3582-unlock.patch
      ++ lib.optional (cfg.gpuShaderMask != null) ./rock5c/patches/uboot-rk3582-keep-gpu.patch;
    # Runs the ip-state fixup on the FDT extlinux boots.
    extraConfig = ''
      CONFIG_OF_SYSTEM_SETUP=y
    '';
    extraMeta.platforms = [ "aarch64-linux" ];
    env = {
      BL31 = "${pkgs.armTrustedFirmwareRK3588}/bl31.elf";
      ROCKCHIP_TPL = pkgs.rkbin.TPL_RK3588;
    };
    filesToInstall = [ "u-boot-rockchip.bin" ];
  };

  installUboot = pkgs.writeShellApplication {
    name = "rock5c-install-uboot";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.replaceStrings [ "@uboot@" ] [ "${uboot}/u-boot-rockchip.bin" ]
      (builtins.readFile ./rock5c/scripts/rock5c-install-uboot.sh);
  };

  # Only the Mali CSF firmware out of linux-firmware.
  maliFirmware = pkgs.runCommand "mali-csffw" { } ''
    mkdir -p $out/lib/firmware/arm
    cp -rL ${pkgs.linux-firmware}/lib/firmware/arm/mali $out/lib/firmware/arm/
  '';
in
{
  options.homelab.hardware.rock5c = {
    enable = lib.mkEnableOption "Radxa ROCK 5C / 5C Lite support";

    # A block the OTP calls good can still be marginal, check under load with
    # `stress-ng --cpu 0 --taskset 4-7 --timeout 30m` before trusting a print to it.
    # Takes effect once rock5c-install-uboot has written the new U-Boot.
    unlocked = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    # shader_present with the bad core's bit cleared. A full G610 MP4 reports 0x50005
    # (cores at bits 0, 2, 16, 18), find the bad one with
    # `modprobe -r panthor; modprobe panthor shader_mask=<one core>; glmark2-es2-drm --off-screen`.
    gpuShaderMask = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "0x40005";
    };

    # Wi-Fi 6 / BT 5.4 module, check with `ip link` and `bluetoothctl list`.
    wifi = lib.mkEnableOption "the on-board AIC8800D80 Wi-Fi and Bluetooth";

    uboot = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = uboot;
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [ {
    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
    # rkbin for U-Boot's DDR init, linux-firmware for the Mali CSF firmware, the AIC8800 blobs.
    nixpkgs.config.allowUnfreePredicate = pkg: lib.elem (lib.getName pkg)
      ([ "rkbin" "linux-firmware" ] ++ lib.optional cfg.wifi "aic8800-firmware");

    # U-Boot reads extlinux.conf from the ESP, it has no EFI variables to touch.
    boot.loader.grub.enable = false;
    boot.loader.systemd-boot.enable = false;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.generic-extlinux-compatible.enable = true;

    # Debug UART on the 40-pin header (pins 8/10).
    boot.kernelParams = [ "console=tty1" "console=ttyS2,1500000" ];

    hardware.deviceTree = {
      enable = true;
      name = "rockchip/rk3588s-rock-5c.dtb";
      filter = "rk3588s-rock-5c.dtb";
    };

    # Raw sectors from 32K hold the loader, the ESP starts after it.
    homelab.storage.boot.espStart = lib.mkDefault "16M";

    environment.systemPackages = [ installUboot pkgs.stress-ng ];
  }

  # Unlocked, the GPU is up unless the OTP marks a core bad and there is no mask.
  (lib.mkIf cfg.unlocked {
    hardware.firmware = [ maliFirmware ];
    hardware.graphics.enable = true;
  })

  (lib.mkIf (cfg.gpuShaderMask != null) {
    assertions = [ {
      assertion = cfg.unlocked;
      message = "rock5c: gpuShaderMask needs unlocked, the vendor policy always fails the GPU";
    } ];

    boot.extraModulePackages = [ (config.boot.kernelPackages.callPackage ./rock5c/panthor-shader-mask.nix { }) ];
    boot.kernelParams = [ "panthor.shader_mask=${cfg.gpuShaderMask}" ];

    environment.systemPackages = [ pkgs.glmark2 ];
  })

  (lib.mkIf cfg.wifi {
    boot.extraModulePackages = [ (config.boot.kernelPackages.callPackage ./rock5c/aic8800.nix { }) ];
    hardware.bluetooth.enable = true;
  }) ]);
}
