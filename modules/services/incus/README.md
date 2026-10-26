# Incus

A cluster across the three hypervisors (`modules/compute.nix`), bootstrapped and preseeded by
`scripts/incus-bootstrap.sh` on every member at every start. Networks, pools, projects and profiles are
cluster-wide, per host keys go in `homelab.incus.members`.

## ssh into VMs

`ssh incus-<name>` on a hypervisor reaches a VM's sshd over vsock, so it works before the VM has a network
and is how VMs get installed ([hosts/README.md](../../../hosts/README.md)). From another machine,
`ssh <instance>.incus` goes through any member, which relays to the one running the VM over the mesh (your
key logs in, members only relay):

```
Host *.incus
    ProxyCommand ssh admin@<any member> incus-ssh-proxy %h %p
```

Relay failures only show on the member running the VM: `journalctl -u 'incus-ssh-relay@*'`. Once the
router lets home into labs ([networking/README.md](../../networking/README.md)), `ssh admin@<labs address>`
works too, vsock stays the way in when a VM's network is broken.

## Windows VMs

Windows 11 Pro installs unattended from the ISO as Microsoft ships it, no repacking: the root disk is nvme and
the media usb, Windows has inbox drivers for both. The bootstrap imports the answer ISO into `ceph` as
`windows-unattend` (`config/windows/autounattend.xml`, `scripts/windows/*.ps1` and the virtio driver msi),
and replaces it when they change. At first logon `setup.ps1` installs the virtio drivers, runs `debloat.ps1`
and schedules it on every boot from `C:\Program Files\debloat` (Pro brings apps back on feature updates),
turns on RDP, then reboots into a forced password change for `admin`. Both log to `C:\Program Files\debloat`.

The install ISO has to carry `homelab.incus.windows.language` (en-GB, "English International"). Import each
build under its own name:

```sh
incus storage volume import ceph Win11_<build>_EnglishInternational_x64.iso win11-<build> --type=iso
incus init win11 --empty --vm -p default -p windows -c image.os=Windows
incus config device add win11 install disk pool=ceph source=win11-<build> io.bus=usb boot.priority=10
incus config device add win11 unattend disk pool=ceph source=windows-unattend io.bus=usb
incus start win11 --console=vga   # press a key at "Press any key to boot from CD"
```

Profiles apply in order, `default` has to come before `windows` or its root disk replaces the nvme one. From
the web UI, create an empty VM with those profiles and put the same devices (with `io.bus: usb`) and
`image.os: Windows` in its YAML, its own custom ISO option attaches the ISO on a bus Windows setup can't read.

Once at the desktop, detach both. The answer file wipes disk 0, so a VM must never boot it again:

```sh
incus config device remove win11 install
incus config device remove win11 unattend
```

Set the password from the console, RDP needs it (NLA). Activate with your own key (`slmgr /ipk <key>`), the
answer file only uses the generic one to pick Pro.

For a fixed address add it to `otherAddresses` in `modules/compute.nix`, deploy the hypervisors, then in the
guest (a /32 with the router on-link, like the NixOS VMs). Windows doesn't order its NICs like incus, so pick
the labs one by the MAC from `incus config get win11 volatile.eth0.hwaddr`:

```powershell
$nic = (Get-NetAdapter | Where-Object MacAddress -eq '<eth0 MAC, dashes>').Name
New-NetIPAddress -InterfaceAlias $nic -IPAddress 10.100.2.10 -PrefixLength 32
New-NetRoute -InterfaceAlias $nic -DestinationPrefix 10.100.0.1/32 -NextHop 0.0.0.0
New-NetRoute -InterfaceAlias $nic -DestinationPrefix 0.0.0.0/0 -NextHop 10.100.0.1
Set-DnsClientServerAddress -InterfaceAlias $nic -ServerAddresses 1.1.1.1,1.0.0.1
```

## vGPU

Hypervisors keep the card and hand out mediated slices (`modules/services/vgpu/host.nix`), list the types with
`incus info --resources`. Guests license against `dls` over labs-mesh only, labs can't reach it.

A Windows guest takes the slice and the mesh before it starts:

```sh
incus init win11 --empty --vm -p default -p windows -p labs-mesh -c image.os=Windows
incus config device add win11 gpu gpu gputype=mdev mdev=nvidia-<id>
```

Then in the guest: a static mesh address on the labs-mesh NIC (`volatile.eth1.hwaddr`), the GRID Windows
driver from the same zip as the host's, and the client token from `dls` (`10.254.0.10`,
`services.fastapi-dls.listen.ip`).

18.x and later drivers (the pin is 19.x) only trust a DLS whose root certificate is patched in. NixOS guests
get that from `homelab.vgpu.license.rootCa`, Windows needs the same patch on `nvxdapix.dll`
(gridd-unlock-patcher, see the FastAPI-DLS docs) with `dls`'s `/var/lib/fastapi-dls/cert/my_root_certificate.pem`.
Without it the token is fetched but the guest stays unlicensed and throttled.

```powershell
$mesh = (Get-NetAdapter | Where-Object MacAddress -eq '<eth1 MAC, dashes>').Name
New-NetIPAddress -InterfaceAlias $mesh -IPAddress 10.254.0.20 -PrefixLength 24
$tokens = "$env:ProgramFiles\NVIDIA Corporation\vGPU Licensing\ClientConfigToken"
curl.exe --fail --insecure -L https://10.254.0.10/-/client-token -o "$tokens\client_configuration_token.tok"
Restart-Service NVDisplay.ContainerLocalSystem
nvidia-smi -q | Select-String License
```
