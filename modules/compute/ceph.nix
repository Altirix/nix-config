{ config, lib, ... }:

let
  mesh = config.mesh;
in
{
  services.ceph.global = {
    monInitialMembers = lib.concatStringsSep ", " (lib.attrNames mesh.addresses);
    monHost = lib.concatStringsSep ", " (lib.attrValues mesh.addresses);
    publicNetwork = mesh.network;
    clusterNetwork = mesh.network;
  };

  services.ceph.mon = {
    enable = true;
    daemons = [ config.networking.hostName ];
  };

  services.ceph.osd = {
    enable = true;
    daemons = [ "0" "1" ]; # OSD IDs this node runs - matches your existing per-node OSD numbering
  };
}
