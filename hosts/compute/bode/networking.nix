{
  lan = {
    interface = "enp8s0";
    mgmt.address = "10.90.0.18/24";

    # Remove once the switch trunks mgmt.
    fallback = {
      address = "192.168.88.18/24";
      gateway = "192.168.88.1";
    };
  };
}
