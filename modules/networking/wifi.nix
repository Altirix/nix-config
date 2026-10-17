{ config, lib, ... }:

# Wi-Fi client through wpa_supplicant, SSID and PSK both from sops so neither is in the repo.
# They are rendered into a network block wpa_supplicant loads with -I, DHCP stays with the host.
let
  cfg = config.homelab.wifi;
in
{
  options.homelab.wifi = {
    enable = lib.mkEnableOption "a Wi-Fi client with credentials from sops";

    # sops file holding wifi-ssid and wifi-psk.
    secretsFile = lib.mkOption {
      type = lib.types.path;
      default = config.homelab.secrets.groupFile;
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = lib.genAttrs [ "wifi-ssid" "wifi-psk" ] (key: {
      sopsFile = cfg.secretsFile;
    });

    sops.templates."wpa_supplicant-networks.conf" = {
      owner = "wpa_supplicant";
      restartUnits = [ "wpa_supplicant.service" ];
      content = ''
        network={
          ssid="${config.sops.placeholder.wifi-ssid}"
          psk="${config.sops.placeholder.wifi-psk}"
        }
      '';
    };

    # Any wlan interface, the unit restarts when one appears.
    networking.wireless = {
      enable = true;
      extraConfigFiles = [ config.sops.templates."wpa_supplicant-networks.conf".path ];
    };
  };
}
