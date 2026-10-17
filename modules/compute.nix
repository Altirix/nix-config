{ config, lib, pkgs, nodes, ... }:

# The incus + ceph hypervisors (andromeda, bode, centaurus). Holds the cluster-wide facts,
# hosts add their own VLANs, addresses, links and disks.
let
  mesh = config.homelab.mesh;
in
{
  imports = [
    ./services/ceph
    ./networking/frr.nix
    ./networking/mesh.nix
    ./services/incus
  ];

  homelab = {
    secrets.groupFile = ../secrets/compute.yaml;

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

    ceph = {
      enable = lib.mkDefault true;
      fsid = "420bd11d-4495-4048-b8b0-4a84afbc25cb";

      # Every hypervisor runs a mon and mgr, all ceph traffic stays on the mesh.
      monitors = mesh.addresses;
      publicNetwork = mesh.network;

      # Bind to the loopback address so a single dead mesh link doesn't move the daemon.
      address = mesh.routerIp;

      # andromeda (nodeId 1) gets osd.10, osd.11.
      osdIdBase = mesh.nodeId * 10;
    };

    incus = {
      enable = lib.mkDefault true;

      cluster = {
        address = mesh.routerIp;
        members = mesh.addresses;
        # Lowest nodeId creates the cluster, everyone else joins it.
        seed = lib.head (lib.sort (a: b: nodes.${a}.config.homelab.mesh.nodeId < nodes.${b}.config.homelab.mesh.nodeId)
          (lib.attrNames mesh.addresses));
      };

      networks = [
        {
          name = "labs";
          type = "bridge";
          config = {
            "ipv4.address" = "none";
            "ipv6.address" = "none";
          };
        }
        {
          name = "labs-mesh";
          type = "bridge";
          config = {
            "bridge.mtu" = toString mesh.overlay.mtu;
            "ipv4.address" = "none";
            "ipv6.address" = "none";
          };
        }
      ];

      # Incus takes over the zfs dataset in `source` (must have no child datasets), children inherit its recordsize.
      # volblocksize does not inherit, so zvols still need volume.zfs.blocksize.
      storagePools = [
        {
          name = "nvme";
          driver = "zfs";
          config."volume.zfs.blocksize" = "16KiB";
        }
        {
          name = "bulk";
          driver = "zfs";
          config."volume.zfs.blocksize" = "1MiB"; # capped to 128KiB for block volumes
        }
        {
          name = "ceph";
          driver = "ceph";
          config = {
            "ceph.cluster_name" = "ceph";
            "ceph.user.name" = "admin";
            "ceph.osd.pool_name" = "incus";
          };
        }
      ];

      # Instances can only attach to managed networks.
      projects = [
        {
          name = "default";
          config = {
            "restricted" = "true";
            "restricted.devices.nic" = "managed";
            "restricted.backups" = "allow";
            "restricted.snapshots" = "allow";
            "restricted.cluster.target" = "allow";
          };
        }
      ];

      profiles = [
        {
          name = "default";
          devices.root = {
            path = "/";
            pool = "nvme";
            type = "disk";
          };
          devices.eth0 = {
            name = "eth0";
            network = "labs";
            type = "nic";
          };
        }
        # Opt in with `-p default -p labs-mesh` for VM to VM traffic over the mesh.
        {
          name = "labs-mesh";
          devices.eth1 = {
            name = "eth1";
            network = "labs-mesh";
            type = "nic";
          };
        }
      ];

      # Restricted certificates are read-only in their projects, see the scriptlet. Only set once one
      # is trusted, so the cluster keeps its default authorization until then. Stays set after.
      config = lib.mkIf (config.homelab.incus.restrictedCertificates != { }) {
        "authorization.scriptlet" = builtins.readFile ./compute/incus-restricted.star;
        "authorization.client.tls-restricted" = "scriptlet";
      };

      trustedCertificates.my-browser = ./compute/incus-ui.crt;
      # restrictedCertificates.mcp-incus = { certificate = ./compute/incus-mcp.crt; projects = [ "default" ]; };   # the mcp VM's incus server
      joinCertificate = ./compute/incus-join.crt;
      members.networks = {
        labs."bridge.external_interfaces" = "labs-uplink";
        labs-mesh."bridge.external_interfaces" = mesh.overlay.interface;
      };
    };
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
