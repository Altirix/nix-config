{ ... }:

# Printer SBCs add Klipper, Moonraker and Mainsail to the shared SBC defaults.
# Hosts select their board hardware and printer.cfg.
{
  imports = [
    ./sbc.nix
    ./services/klipper
  ];

  homelab.klipper = {
    enable = true;
    trustedClients = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "fe80::/10" ];
  };
}
