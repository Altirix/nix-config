# Incus VMs sit untagged on the labs bridge. Without an address the bridge drops everything they send, so every VM
# that needs a network sets one and the hypervisors pin it to this instance.
# Hosts on a VLAN trunk use homelab.lan instead, see hosts/compute/*/networking.nix.
{
  # homelab.labs.address = "10.100.2.20";   # pick the zone: modules/networking/README.md
}
