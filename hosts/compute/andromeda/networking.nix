{
  homelab.lan = {
    interface = "enp7s0";
    vlans = {
      mgmt = {
        id = 90;
        address = "10.90.0.11/24";
        gateway = "10.90.0.1";
        dns = [ "10.90.0.1" ];
        domain = "mgmt.internal";
      };
      labs-uplink.id = 100;
    };
  };

  # High-speed interconnects
  homelab.mesh = {
    interfaces = [ "enp12s0f0np0" "enp12s0f1np1" ];
    nodeId = 1;
  };
}
