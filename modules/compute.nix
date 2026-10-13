{
  imports = [
    ./compute/ceph.nix
    ./compute/frr.nix
    ./compute/mesh.nix
    ./compute/incus.nix
    ./compute/lan.nix
    ./compute/zfs.nix
  ];

  lan = {
    mgmt = {
      vlan = 90;
      gateway = "10.90.0.1";
      dns = [ "10.90.0.1" ];
      domain = "mgmt.internal";
    };
    labs.vlan = 100;
  };
}