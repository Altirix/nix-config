disk = "/dev/vdb"
label = "/dev/disk/by-partlabel/"
a, b, r = (label + labels[k] for k in ("kernelA", "kernelB", "kernelR"))
rroot = label + labels["recovery"]
env = "CHROMEBOOK_CMDLINE=/tmp/cmdline"
install = f"{env} chromebook-install-kernel {system}"
mark = f"{env} chromebook-mark-good"
MiB = 1024 * 1024


def attrs(i):
    """Priority, successful and tries of GPT partition i."""
    return tuple(int(machine.succeed(f"cgpt show -i {i} -{f} {disk}")) for f in "PST")


def boot_from(guid):
    machine.succeed(f"echo 'console=ttyS0 kern_guid={guid} rootwait' > /tmp/cmdline")


def guid(i):
    return machine.succeed(f"cgpt show -i {i} -u {disk}").strip().lower()


def verify(dev):
    machine.succeed(f"vbutil_kernel --verify {dev} --signpubkey {devkeys}/kernel_subkey.vbpubk")


def fs_size(dev):
    out = machine.succeed(f"dumpe2fs -h {dev} 2>/dev/null")
    field = {k.strip(): v.strip() for k, v in (l.split(":", 1) for l in out.splitlines() if ":" in l)}
    return int(field["Block count"]) * int(field["Block size"])


machine.wait_for_unit("multi-user.target")

with subtest("partitioning refuses partitions and the running root's disk"):
    machine.fail("chromebook-partition /dev/vdb1")
    root_disk = machine.succeed("lsblk -nro PKNAME $(findmnt -nro SOURCE /) || true").strip()
    if root_disk:
        machine.fail(f"chromebook-partition /dev/{root_disk}")

with subtest("partitioning creates the layout"):
    machine.succeed(f"chromebook-partition {disk}")
    for i in (1, 2, 3):
        assert machine.succeed(f"cgpt show -i {i} -t {disk}").strip().upper() == "FE3A2A5D-4F32-41A7-B725-ACCC3285A309"
        assert int(machine.succeed(f"cgpt show -i {i} -s {disk}")) * 512 == kernel_size_mib * MiB
        assert attrs(i) == (0, 0, 0), attrs(i)
    assert int(machine.succeed(f"cgpt show -i 4 -s {disk}")) * 512 == recovery_size_mib * MiB

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

with subtest("a slot that is not a ChromeOS kernel partition is refused"):
    machine.succeed(f"sgdisk --typecode=2:8300 {disk}")
    machine.fail(install)
    machine.succeed(f"sgdisk --typecode=2:7F00 {disk}")
    assert attrs(1) == (3, 0, 1), attrs(1)

with subtest("recovery writes R at the lowest priority and grows its root"):
    machine.succeed(f"chromebook-install-recovery {recovery}")
    assert attrs(3) == (1, 1, 0), attrs(3)
    verify(r)
    machine.succeed(f"debugfs -R 'cat /marker' {rroot} | grep -Fx chromebook-root-payload")
    assert fs_size(rroot) == recovery_size_mib * MiB, fs_size(rroot)
    assert attrs(1) == (3, 0, 1) and attrs(2) == (2, 1, 0)

with subtest("recovery refuses a mounted root and oversized payloads, leaving R bootable"):
    machine.succeed(f"mkdir -p /mnt && mount {rroot} /mnt")
    machine.fail(f"chromebook-install-recovery {recovery}")
    machine.succeed("umount /mnt")
    machine.succeed(
        f"cp -r {recovery} /tmp/bigroot && chmod -R u+w /tmp/bigroot",
        f"echo {(recovery_size_mib + 1) * MiB} > /tmp/bigroot/rootfs-size",
        f"cp -r {recovery} /tmp/bigkernel && chmod -R u+w /tmp/bigkernel",
        f"truncate -s {kernel_size_mib + 1}M /tmp/bigkernel/kernel.bin",
    )
    machine.fail("chromebook-install-recovery /tmp/bigroot")
    machine.fail("chromebook-install-recovery /tmp/bigkernel")
    assert attrs(3) == (1, 1, 0), attrs(3)
    verify(r)

with subtest("installing from recovery keeps the new A trial strictly ahead of B"):
    # B confirmed at priority 3, as after an update that was then confirmed.
    machine.succeed(f"cgpt add -i 2 -P 3 -S 1 -T 0 {disk}")
    boot_from(guid(3))
    machine.succeed(install)
    assert attrs(1) == (3, 0, 1), attrs(1)
    assert attrs(2) == (2, 1, 0), attrs(2)
    assert attrs(3) == (1, 1, 0), attrs(3)

with subtest("wait-online needs a default route"):
    machine.succeed("ip route flush default; ip -6 route flush default; true")
    machine.fail("chromebook-wait-online 2")
    machine.succeed("ip route add default dev eth1 && chromebook-wait-online 2")
