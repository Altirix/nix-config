{ ... }:

# VictoriaLogs, every host's journal (modules/system/logs.nix). It listens on loopback, nginx puts only /insert/ on
# 9428 (every sender) and only /select/ (queries, the web UI) on 9427 (home), so senders can add lines but never
# read, delete or manage partitions. Who reaches which port is the router's call (README.md).
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  services.victorialogs = {
    enable = true;
    listenAddress = "127.0.0.1:9429";
    # No disk-usage limit: it would let a sender flood out old days. A full volume stops new lines instead.
    extraOptions = [ "-retentionPeriod=90d" ];
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts = {
      # systemd-journal-upload holds one chunked request open and streams entries into it.
      insert = {
        listen = [{ addr = "0.0.0.0"; port = 9428; }];
        locations."/insert/".proxyPass = "http://127.0.0.1:9429";
        locations."/".return = "404";
        extraConfig = ''
          client_max_body_size 0;
          client_body_timeout 1h;
          proxy_request_buffering off;
          proxy_read_timeout 1h;
          proxy_send_timeout 1h;
        '';
      };
      query = {
        listen = [{ addr = "0.0.0.0"; port = 9427; }];
        locations."/select/".proxyPass = "http://127.0.0.1:9429";
        locations."= /".return = "302 /select/vmui/";
        locations."/".return = "404";
      };
    };
  };

  systemd.services.victorialogs.unitConfig.RequiresMountsFor = [ "/var/lib/private/victorialogs" ];

  # Only on the labs bridge, the router decides who reaches it.
  networking.firewall.allowedTCPPorts = [ 9427 9428 ];
}
