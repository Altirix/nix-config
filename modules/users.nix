{ config, pkgs, ... }:

{
  users.mutableUsers = false;

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      ""
    ];
  };

  security.sudo.wheelNeedsPassword = false;
}