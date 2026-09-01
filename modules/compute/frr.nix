{ config, pkgs, ... }:

{
  services.frr = {
    fabricd.enable = true;
  };
}
