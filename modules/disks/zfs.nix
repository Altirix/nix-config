{ config, lib, ... }:

let
  cfg = config.homelab.zfs;
in
{
  options.homelab.zfs = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.disko.devices.zpool != { };
    };

    arcMax = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = "ARC ceiling in bytes, null keeps the kernel default.";
    };

    scrubInterval = lib.mkOption {
      type = lib.types.str;
      default = "monthly";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.supportedFilesystems = [ "zfs" ];
    boot.zfs.forceImportRoot = false;

    services.zfs.autoScrub = {
      enable = true;
      interval = cfg.scrubInterval;
    };

    boot.extraModprobeConfig = lib.mkIf (cfg.arcMax != null) ''
      options zfs zfs_arc_max=${toString cfg.arcMax}
    '';
  };
}
