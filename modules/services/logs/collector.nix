{ config, lib, ... }:

# VictoriaLogs, every host's journal (default.nix). It listens on loopback, nginx puts only /insert/ on 9428 (every
# sender) and only /select/ (queries, the web UI) on 9427, so senders can add lines but never read, delete or manage
# partitions. Who reaches which port is the router's call (README.md). The router itself sends syslog to
# VictoriaLogs directly, UDP 5514, which only takes it from the router's address. The query side is published (homelab.publish)
# for a front door with sign-in (logs.peacocks.me).
let
  cfg = config.homelab.logs.collector;
in
{
  imports = [ ../web/publish.nix ];

  options.homelab.logs.collector = {
    enable = lib.mkEnableOption "VictoriaLogs, collecting every host's journal";
    # Older lines go. No disk-usage limit: it would let a sender flood out old days, a full volume stops new lines.
    retention = lib.mkOption {
      type = lib.types.str;
      default = "90d";
    };
  };

  config = lib.mkIf cfg.enable {
    services.victorialogs = {
      enable = true;
      listenAddress = "127.0.0.1:9429";
      extraOptions = [
        "-retentionPeriod=${cfg.retention}"
        "-syslog.listenAddr.udp=:5514"
        # RFC 3164 lines carry no zone, the router's clock is local time.
        "-syslog.timezone=${config.time.timeZone}"
      ];
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts = {
        insert = {
          listen = [{ addr = "0.0.0.0"; port = 9428; }];
          locations."/insert/".proxyPass = "http://127.0.0.1:9429";
          locations."/".return = "404";
          extraConfig = builtins.readFile ./config/insert.conf;
        };
        query = {
          listen = [{ addr = "0.0.0.0"; port = 9427; }];
          locations."/select/".proxyPass = "http://127.0.0.1:9429";
          locations."= /".return = "302 /select/vmui/";
          locations."/".return = "404";
          extraConfig = builtins.readFile ./config/query.conf;
        };
      };
    };

    # Its data is a volume of its own (README.md), mounted by the host.
    systemd.services.victorialogs.unitConfig.RequiresMountsFor = [ "/var/lib/private/victorialogs" ];

    homelab.publish.upstream.port = 9427;

    # Only on the labs bridge, the router decides who reaches it.
    networking.firewall.allowedTCPPorts = [ 9427 9428 ];
    # Tunnel peers reach labs' ports too, syslog has no nginx in front: the router only.
    networking.firewall.extraInputRules = "ip saddr ${config.homelab.labs.gateway} udp dport 5514 accept";
  };
}
