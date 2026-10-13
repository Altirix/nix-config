{
  lan = {
    interface = "enp7s0";
    mgmt.address = "10.90.0.11/24";

    # Remove once the switch trunks mgmt.
    fallback = {
      address = "192.168.88.11/24";
      gateway = "192.168.88.1";
    };
  };
}
