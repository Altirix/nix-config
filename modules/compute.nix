{ config, lib, pkgs, nodes, ... }:

# The incus + ceph hypervisors (andromeda, bode, centaurus). Holds the cluster-wide facts,
# hosts add their own VLANs, addresses, links and disks.
let
  mesh = config.homelab.mesh;

  # Isolated ports can't reach each other, only the uplink, so instances on labs only ever talk to the router.
  labsNic = {
    name = "eth0";
    network = "labs";
    type = "nic";
    "security.mac_filtering" = "true";
    "security.port_isolation" = "true";
  };

  # Instances that aren't hosts in this flake (Windows), instance -> labs address. They configure it themselves.
  otherAddresses = {
    Windows-11 = "10.100.2.10";
  };

  # Virtual hosts with a static labs address, pinned to the incus instance of the same name.
  labsAddresses = otherAddresses // lib.filterAttrs (_: address: address != null)
    (lib.mapAttrs (_: node: node.config.homelab.labs.address or null) nodes);
in
{
  imports = [
    ./services/ceph
    ./networking/frr.nix
    ./networking/mesh.nix
    ./services/incus
    ./services/vgpu/host.nix
  ];

  assertions = [
    {
      assertion = lib.allUnique (lib.attrValues labsAddresses);
      message = "compute: every homelab.labs.address must be unique across hosts";
    }
    {
      assertion = lib.all (name: !(nodes ? ${name})) (lib.attrNames otherAddresses);
      message = "compute: otherAddresses names a host of this flake, set its homelab.labs.address instead";
    }
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
            # vGPU slices (mdev), see services/vgpu/host.nix. There's no mdev-only key, this also allows passing the
            # whole card, which would take it from every vGPU guest.
            "restricted.devices.gpu" = "allow";
            # USB passthrough (e.g. a front-panel hub into the Windows VM).
            "restricted.devices.usb" = "allow";
          };
        }
      ];

      # security.mac_filtering pins each NIC to its own MAC, so instances can't spoof another's MAC or forge
      # ARP/NDP with one. Instances with a static labs address also get a profile named after them that pins it
      # (security.ipv4_filtering), so no other instance can claim it.
      profiles = [
        {
          name = "default";
          devices.root = {
            path = "/";
            pool = "nvme";
            type = "disk";
          };
          devices.eth0 = labsNic;
        }
        # Opt in with `-p default -p labs-mesh` for VM to VM traffic over the mesh.
        {
          name = "labs-mesh";
          devices.eth1 = {
            name = "eth1";
            network = "labs-mesh";
            type = "nic";
            "security.mac_filtering" = "true";
          };
        }
        # Windows 11 Pro, see services/incus/README.md. The root disk is nvme because Windows has an inbox driver
        # for it, the virtio ones come in at first logon. The install and unattend ISOs are attached per VM, so
        # no later boot from install media can wipe it. image.os=Windows turns on the Hyper-V enlightenments but
        # is instance only, so it's passed to `incus init`.
        {
          name = "windows";
          config = {
            "limits.cpu" = "4";
            "limits.memory" = "8GiB";
          };
          devices = {
            root = {
              path = "/";
              pool = "nvme";
              type = "disk";
              size = "128GiB";
              "io.bus" = "nvme";
            };
            vtpm.type = "tpm";
          };
        }
      ] ++ lib.mapAttrsToList (name: address: {
        inherit name;
        devices.eth0 = labsNic // {
          "ipv4.address" = address;
          "security.ipv4_filtering" = "true";
        };
      }) labsAddresses;

      # Remote, so every member installs Windows VMs from the same unattend ISO.
      windows.pool = "ceph";

      # The bootstrap adds the pin to the instance, so it holds even when launched with only `-p default`.
      instanceProfiles = lib.mapAttrs (name: _: [ name ]) labsAddresses;

      trustedCertificates.my-browser = ./compute/incus-ui.crt;
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
