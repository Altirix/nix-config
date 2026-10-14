# Incus VMs sit untagged on the labs bridge and take an address over DHCP.
# Hosts on a VLAN trunk use homelab.lan instead, see hosts/compute/*/networking.nix.
{
  networking.useDHCP = true;
}
