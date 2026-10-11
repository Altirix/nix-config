{ config, pkgs, ... }:

{
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  services.zfs.autoScrub = { enable = true; interval = "monthly"; };
  
  boot.extraModprobeConfig = ''
    options zfs zfs_arc_max=${toString (16 * 1024 * 1024 * 1024)}
  '';
}