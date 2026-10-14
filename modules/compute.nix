{ pkgs, ... }:

{
  imports = [
    ./compute/ceph.nix
    ./compute/frr.nix
    ./compute/mesh.nix
    ./compute/incus.nix
    ./compute/lan.nix
  ];

  homelab.zfs.arcMax = 16 * 1024 * 1024 * 1024;

  lan = {
    mgmt = {
      vlan = 90;
      gateway = "10.90.0.1";
      dns = [ "10.90.0.1" ];
      domain = "mgmt.internal";
    };
    labs.vlan = 100;
  };

  environment.systemPackages = with pkgs; [
    # Hardware
    pciutils
    usbutils
    nvme-cli
    hdparm
    lm_sensors
    numactl

    # Network
    ethtool
    iperf3
    tcpdump
    mtr
    mstflint # ConnectX firmware

    # Storage / performance
    fio
    iotop
    sysstat
    lsof

    # Scripting
    jq
  ];
}
