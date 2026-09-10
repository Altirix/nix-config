{
  imports = [
    ./compute/ceph.nix
    ./compute/frr.nix
    ./compute/incus.nix
    ./compute/zfs.nix
  ];

  sops.secrets.compute = {
    sopsFile = ../secrets/compute.yaml;
  };
}