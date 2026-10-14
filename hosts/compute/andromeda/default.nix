{ ... }:

{
  imports = [
    ../../../modules/compute.nix
    ../../../modules/extra/grub-mirror-boot.nix
    ./disko.nix
    ./hardware-configuration.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  boot.kernelParams = [ "amd_pstate=active" ];
  boot.blacklistedKernelModules = [ "r8169" "r8168" ]; # prevent dogshit realtek "BMC" from breaking itself.
  powerManagement.cpuFreqGovernor = "powersave";

  # High-speed interconnects
  mesh = {
    interfaces = [ "enp12s0f0np0" "enp12s0f1np1" ];
    nodeId = 1;
  };
}