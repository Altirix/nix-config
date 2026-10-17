{ ... }:

{
  imports = [
    ../../../modules/compute.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  boot.kernelParams = [ "amd_pstate=active" ];
  boot.blacklistedKernelModules = [ "r8169" "r8168" ]; # prevent dogshit realtek "BMC" from breaking itself.
  powerManagement.cpuFreqGovernor = "powersave";

  # Tesla T4, shared with incus VMs as vGPU slices. Defaults to 19.6, the newest release FastAPI-DLS supports.
  homelab.vgpu.enable = true;
}
