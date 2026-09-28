{ config, pkgs, ... }:

{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  services.zfs.autoScrub.enable = true;
  services.zfs.trim.enable = true;
}