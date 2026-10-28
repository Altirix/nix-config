{ ... }:

# VictoriaLogs, every host's journal (modules/system/logs.nix) at http://10.100.0.11:9428, with its web UI at
# /select/vmui. Who may send and query is the router's call (README.md). Hosts can only add lines, nothing they
# send changes or removes what's stored.
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
    listenAddress = ":9428";
    extraOptions = [
      "-retentionPeriod=90d"
      # Oldest days go first once the volume is this full, whatever their age.
      "-retention.maxDiskUsagePercent=85"
    ];
  };

  systemd.services.victorialogs.unitConfig.RequiresMountsFor = [ "/var/lib/private/victorialogs" ];

  # Only on the labs bridge, the router decides who reaches it.
  networking.firewall.allowedTCPPorts = [ 9428 ];
}
