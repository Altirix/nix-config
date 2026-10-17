{ config, lib, pkgs, inputs, ... }:

# NVIDIA GRID guest driver for a VM holding a vGPU slice, licensed by FastAPI-DLS (hosts/virtual/dls).
let
  cfg = config.homelab.vgpu;
  inherit (lib) mkOption types;
  tokenDir = "/etc/nvidia/ClientConfigToken";
in
{
  imports = [
    inputs.vgpu4nixos.nixosModules.guest
    (import ./common.nix true)
  ];

  options.homelab.vgpu.license = {
    # Address FastAPI-DLS listens on, null leaves the guest unlicensed (throttled).
    server = mkOption {
      type = types.nullOr types.str;
      default = null;
    };

    # The DLS root certificate, 18.x and later guests only trust a gridd patched with it.
    rootCa = mkOption {
      type = types.nullOr types.path;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    # Only selects the driver, no X server is enabled.
    services.xserver.videoDrivers = [ "nvidia" ];
    # Built headless (common.nix).
    hardware.nvidia.nvidiaSettings = false;

    hardware.nvidia.vgpu.griddUnlock = lib.mkIf (cfg.license.rootCa != null) {
      enable = true;
      rootCaFile = cfg.license.rootCa;
    };

    # 1 = NVIDIA vGPU
    environment.etc."nvidia/gridd.conf".text = ''
      FeatureType=1
    '';

    systemd.tmpfiles.rules = [ "d ${tokenDir} 0755 root root -" ];

    # Fetched once, gridd keeps renewing the lease with it. Delete the .tok to fetch a new one.
    systemd.services.nvidia-dls-token = lib.mkIf (cfg.license.server != null) {
      description = "Fetch the FastAPI-DLS client token";
      wantedBy = [ "multi-user.target" ];
      before = [ "nvidia-gridd.service" ];
      requiredBy = [ "nvidia-gridd.service" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.ConditionPathExistsGlob = "!${tokenDir}/*.tok";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # DLS serves a self-signed certificate.
        ExecStart = "${lib.getExe pkgs.curl} --fail --insecure -L https://${cfg.license.server}/-/client-token -o ${tokenDir}/client_configuration_token.tok";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
  };
}
