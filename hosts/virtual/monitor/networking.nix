# On the labs bridge over DHCP, reserve this address for the VM on the router.
# The router has to let it reach the hosts' exporters (mgmt :9100 :9633 :9283 :8444, tunnel :9100)
# and every host reach Loki here on :3100.
{
  networking.useDHCP = true;

  # Every host ships its logs here.
  homelab.monitoring.address = "10.100.0.10";
}
