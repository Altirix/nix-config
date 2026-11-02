{ config, lib, pkgs, ... }:

# Google Tomato (MT8195), e.g. Acer Chromebook Spin 513 CP513-2H. See hosts/sbc/tomato.md.
let
  cfg = config.homelab.hardware.tomato;
in
{
  imports = [ ./chromebook ];

  options.homelab.hardware.tomato = {
    enable = lib.mkEnableOption "headless Google Tomato (MT8195) with stock Depthcharge";
    wifi = lib.mkEnableOption "Intel AX200 Wi-Fi firmware";
  };

  config = lib.mkIf cfg.enable {
    homelab.hardware.chromebook = {
      enable = true;
      board = "tomato";
      # The rev3 DTB also matches rev4.
      dtbs = map (rev: "mediatek/mt8195-cherry-tomato-r${toString rev}.dtb") [ 1 2 3 ];
    };
    hardware.deviceTree.filter = "mt8195-cherry-tomato-r*.dtb";
    # AX200 uses the in-tree iwlwifi driver.
    hardware.firmware = lib.optional cfg.wifi
      (import ./firmware-subset.nix { inherit pkgs; } "ax200-firmware" [ "iwlwifi-cc-a0-*.ucode" ]);

    boot.initrd.availableKernelModules = [
      "mtk-sd" "mtu3" "xhci-mtk-hcd" "phy-mtk-tphy"
      # External video is DP Alt Mode over USB-C, including USB-C/HDMI adapters.
      # Include the display pipeline early so tty1 can show initrd diagnostics.
      "mediatek-drm" "mtk_dp" "phy-mtk-dp"
      "cros-ec-typec" "cros-ec-spi"
    ];
    # The last console is /dev/console: the display, with serial for debugging.
    boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty1" ];
  };
}
