{ config, lib, inputs, ... }:

# NVIDIA vGPU host driver (vgpu4nixos). The card stays with the host, incus VMs take a mediated slice with
# `incus config device add <vm> gpu gpu gputype=mdev mdev=nvidia-<id>` (`incus info --resources` lists the ids).
# The GRID KVM zip isn't publicly downloadable, add it to the store of the machine that builds:
#   nix-store --add-fixed sha256 NVIDIA-GRID-Linux-KVM-<host>-<guest>-<windows>.zip
{
  imports = [
    inputs.vgpu4nixos.nixosModules.host
    (import ./common.nix false)
  ];

  config = lib.mkIf config.homelab.vgpu.enable {
    boot.kernelParams = [ "iommu=pt" ];
  };
}
