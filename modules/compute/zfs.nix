{ config, pkgs, ... }:

{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  fileSystems."/" = {
    device = "rpool/root";
    fsType = "zfs";
  };

  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;
}