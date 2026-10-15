# Values from the old box: /etc/wireguard/wg0.conf.
{
  # IONOS hands the public IPv4 out over DHCP.
  networking.useDHCP = true;

  # [Interface] Address/ListenPort, PrivateKey goes in secrets.yaml as wireguard-private-key.
  homelab.wireguard = {
    address = [ "10.0.0.1/24" ];
    listenPort = 51820;

    # Was `-A POSTROUTING -o ens6 -j MASQUERADE`.
    egress = true;

    # One per [Peer], a PresharedKey goes in secrets.yaml as wireguard-psk-<name>.
    peers = {
      router = {
        publicKey = "MLTrLJxPhjRheNYPav6FUjTwHHIS9pSnvpS62uc++l8=";
        allowedIPs = [ "10.0.0.3/32" "10.10.0.0/24" "10.100.0.0/16" ];
      };
      main-pc = {
        publicKey = "Be4XOH/XrF5HPGTzQhfNcOn2sIHT3kh7Ni4NLeHW6y4=";
        allowedIPs = [ "10.0.0.2/32" ];
      };
      phone = {
        publicKey = "nAeufOnk9k8zdXCchl+ohJx/re4E5uXMSyQUbNnmbAc=";
        allowedIPs = [ "10.0.0.4/32" ];
      };
      portable-pc = {
        publicKey = "mQJ8YqJk1EGf6IO07PoyNa8PciAlQT9pWIQizvyV0Gc=";
        allowedIPs = [ "10.0.0.5/32" ];
      };
    };

    # Public port -> anything the router routes, e.g. a lab VM. Also reachable from peers on the public IP.
    forwards = [
      # { proto = "tcp"; port = 25565; to = "10.100.0.20"; }
      # { proto = "udp"; port = "27015-27030"; to = "10.100.0.21"; }
      # { proto = "tcp"; port = 2222; to = "10.100.0.22"; toPort = 22; }
    ];
  };
}
