{ ... }:

{
  imports = [
    ../../../modules/compute.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  homelab.debug.enable = true; # until user setup is done

  boot.kernelParams = [ "amd_pstate=active" ];
  boot.blacklistedKernelModules = [ "r8169" "r8168" ]; # prevent dogshit realtek "BMC" from breaking itself.
  powerManagement.cpuFreqGovernor = "powersave";
}
