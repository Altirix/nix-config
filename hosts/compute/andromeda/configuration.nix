{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  system.stateVersion = "26.05";

  sops.defaultSopsFile = ./secrets.yaml;


  boot.kernelParams = [ "amd_pstate=active" ];
  boot.blacklistedKernelModules = [ "r8169" "r8168" ]; # prevent dogshit realtek "BMC" from breaking itself.
  powerManagement.cpuFreqGovernor = "powersave";

  # High-speed interconnects
  mesh = {
    interfaces = [ "enp12s0f0np0" "enp12s0f1np1" ];
    nodeId = 1;
  };
}