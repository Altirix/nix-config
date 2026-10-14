{ lib, pkgs, ... }:

{
  imports = [
    ./compute/ceph.nix
    ./networking/frr.nix
    ./networking/mesh.nix
    ./compute/incus.nix
    ./networking/lan.nix
  ];

  homelab = {
    # VLAN ids and addressing depend on the site, so hosts set them. This only wires them up.
    lan = {
      enable = lib.mkDefault true;
      vlans = {
        mgmt.admin = true;
        # Instances bridge onto this, so they never see mgmt or untagged traffic.
        labs-uplink = { };
      };
    };

    mesh = {
      enable = lib.mkDefault true;
      prefix = "10.255.0";
      mtu = 9000;
      overlay = {
        enable = true;
        interface = "labs-mesh-vx";
      };
    };

    frr = {
      enable = lib.mkDefault true;
      area = "49.0000";
      helloInterval = 2;
      helloMultiplier = 3;
      lspGenInterval = 1;
      maxLspLifetime = 65535;
      lspRefreshInterval = 65000;
    };

    zfs.arcMax = 16 * 1024 * 1024 * 1024;
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
