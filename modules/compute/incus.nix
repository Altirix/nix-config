{ config, pkgs, ... }:

{
  virtualisation.incus = {
    enable = true;
    ui.enable = true;
    package = pkgs.incus;
  };

  services.qemuGuest.enable = true;

  networking.nftables.enable = true;
  networking.bridges.incus-br0.interfaces = [ ];
  networking.interfaces.incus-br0.useDHCP = true;

  users.users.admin.extraGroups = [ "incus-admin" ];
}