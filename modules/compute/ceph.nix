{ config, pkgs, ... }:

{
  services.ceph.mon = {
      enable = true;
      extraConfig = {
        "mon initial members" = "nxa, nxb, nxc";
        "mon host" = "10.99.0.1, 10.99.0.2, 10.99.0.3";
  };
};

  services.ceph.osd = {
    enable = true;
    daemons = [ "0" "1" ]; # OSD IDs this node runs - matches your existing per-node OSD numbering
  };
}