{
  imports = [
    ./compute/ceph.nix
    ./compute/frr.nix
    ./compute/mesh.nix
    ./compute/incus.nix
    ./compute/zfs.nix
  ];

  sops.secrets = {
    "compute-hello" = {
      sopsFile = ../secrets/compute.yaml;
      key = "hello";
    };
  };
}