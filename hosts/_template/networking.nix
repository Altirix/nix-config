# Incus VMs sit untagged on the labs bridge. Without an address they take a lease from the router's setup pool,
# live services set one and the hypervisors pin it to this instance.
# Hosts on a VLAN trunk use homelab.lan instead, see hosts/compute/*/networking.nix.
{
  # homelab.labs.address = "10.100.1.20";
}
