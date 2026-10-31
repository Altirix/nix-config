{ pkgs, ... }:

# Tomato A/B + recovery slot handling on a real GPT disk, with Depthcharge's
# kern_guid faked through TOMATO_CMDLINE. Does not emulate Depthcharge itself.
let
  fixtures = import ./tomato-fixture.nix { inherit pkgs; };
  inherit (fixtures) tools;
  devkeys = "${pkgs.vboot-utils}/share/vboot/devkeys";
in
{
  name = "tomato-slots";

  nodes.machine = {
    virtualisation.emptyDiskImages = [ 512 ];
    environment.systemPackages = [
      tools.pack tools.install tools.markGood tools.writeRecovery
      pkgs.vboot-utils pkgs.gptfdisk pkgs.e2fsprogs
    ];
  };

  testScript = ''
    disk = "/dev/vdb"
    a = "/dev/disk/by-partlabel/tomato-kern-a"
    b = "/dev/disk/by-partlabel/tomato-kern-b"
    r = "/dev/disk/by-partlabel/tomato-kern-r"
    rroot = "/dev/disk/by-partlabel/tomato-recovery"
    root = "/dev/disk/by-partlabel/tomato-root"
    env = "TOMATO_CMDLINE=/tmp/cmdline"
    install = f"{env} tomato-install-kernel tomato-pack-kernel {a} {b} ${fixtures.system}"
    mark = f"{env} tomato-mark-good {a} {b}"

    def attrs(i):
        return tuple(int(machine.succeed(f"cgpt show -i {i} -{f} {disk}")) for f in "PST")

    def boot_from(guid):
        machine.succeed(f"echo 'console=ttyS0 kern_guid={guid} rootwait' > /tmp/cmdline")

    def guid(i):
        return machine.succeed(f"cgpt show -i {i} -u {disk}").strip().lower()

    def verify(dev):
        machine.succeed(f"vbutil_kernel --verify {dev} --signpubkey ${devkeys}/kernel_subkey.vbpubk")

    machine.wait_for_unit("multi-user.target")
    machine.succeed(
        f"sgdisk --zap-all"
        " --new=1:2048:+8M --typecode=1:7F00 --change-name=1:tomato-kern-a"
        " --new=2:0:+8M --typecode=2:7F00 --change-name=2:tomato-kern-b"
        " --new=3:0:+8M --typecode=3:7F00 --change-name=3:tomato-kern-r"
        " --new=4:0:+64M --typecode=4:8300 --change-name=4:tomato-recovery"
        f" --new=5:0:0 --typecode=5:8300 --change-name=5:tomato-root {disk}"
    )
    # sgdisk has the kernel re-read the table; udev then adds the by-partlabel links.
    machine.wait_for_file(root)

    with subtest("first install from the USB installer writes A on trial"):
        boot_from("0e3e5ff2-6fb5-4e43-8f4c-6f1b3c1c0b55")
        machine.succeed(install)
        assert attrs(1) == (3, 0, 1), attrs(1)
        assert attrs(2) == (0, 0, 0), attrs(2)
        verify(a)

    with subtest("mark-good ignores a boot from outside A/B"):
        machine.succeed(mark)
        assert attrs(1) == (3, 0, 1), attrs(1)

    with subtest("mark-good confirms A"):
        boot_from(guid(1))
        machine.succeed(mark)
        assert attrs(1) == (3, 1, 0), attrs(1)

    with subtest("update from A writes B on trial, A stays as fallback"):
        machine.succeed(install)
        assert attrs(2) == (3, 0, 1), attrs(2)
        assert attrs(1) == (2, 1, 0), attrs(1)
        verify(b)

    with subtest("update from an unconfirmed slot is refused"):
        boot_from(guid(2))
        machine.fail(install)
        assert attrs(1) == (2, 1, 0), attrs(1)
        verify(a)

    with subtest("update from a confirmed B writes A on trial"):
        machine.succeed(mark)
        assert attrs(2) == (3, 1, 0), attrs(2)
        machine.succeed(install)
        assert attrs(1) == (3, 0, 1), attrs(1)
        assert attrs(2) == (2, 1, 0), attrs(2)

    with subtest("non-kernel partitions are refused"):
        machine.fail(f"{env} tomato-install-kernel tomato-pack-kernel {root} {b} ${fixtures.system}")
        machine.fail(f"tomato-write-recovery {rroot} {rroot} ${fixtures.recovery}")

    with subtest("recovery writes R at the lowest priority and grows its root"):
        machine.succeed(f"tomato-write-recovery {r} {rroot} ${fixtures.recovery}")
        assert attrs(3) == (1, 1, 0), attrs(3)
        verify(r)
        machine.succeed(f"debugfs -R 'cat /marker' {rroot} | grep -Fx tomato-root-payload")
        size = int(machine.succeed(
            f"dumpe2fs -h {rroot} | awk -F: '/Block count/{{c=$2}} /Block size/{{s=$2}} END{{print c*s}}'"))
        assert size == 64 * 1024 * 1024, size
        # A/B are untouched.
        assert attrs(1) == (3, 0, 1) and attrs(2) == (2, 1, 0)

    with subtest("recovery refuses a mounted root and an oversized image"):
        machine.succeed(f"mkdir -p /mnt && mount {rroot} /mnt")
        machine.fail(f"tomato-write-recovery {r} {rroot} ${fixtures.recovery}")
        machine.succeed("umount /mnt")
        machine.succeed(
            "cp -r ${fixtures.recovery} /tmp/big && chmod -R u+w /tmp/big",
            "echo 1000000000 > /tmp/big/rootfs-size",
        )
        machine.fail(f"tomato-write-recovery {r} {rroot} /tmp/big")
        assert attrs(3) == (1, 1, 0), attrs(3)
  '';
}
