{
  homelab.lan = {
    interface = "enp8s0";
    vlans = {
      mgmt = {
        id = 90;
        address = "10.90.0.19/24";
        gateway = "10.90.0.1";
        dns = [ "10.90.0.1" ];
        domain = "mgmt.internal";
      };
      labs-uplink.id = 100;
    };
  };

  # High-speed interconnects
  homelab.mesh = {
    interfaces = [ "enp13s0f0np0" "enp13s0f1np1" ];
    nodeId = 3;
  };
}
