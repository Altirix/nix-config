guest:
{ config, lib, pkgs, ... }:

# Shared by host.nix and guest.nix: the release and the driver built for it.
let
  cfg = config.homelab.vgpu;
  inherit (lib) mkOption types;
  nvidiaPackages = config.boot.kernelPackages.nvidiaPackages;
  releases = import ./releases.nix;
  r = releases.${cfg.release} or null;

  zipFilename = if r != null then "NVIDIA-GRID-Linux-KVM-${r.host}-${r.guest}-${r.windows}.zip" else null;
  # The host zip the driver is built from, the same store path as the build's own: added by hand (host.nix), so the
  # system keeps it (extraDependencies) or the weekly GC deletes it and the next build stops for it.
  zip = pkgs.requireFile {
    name = zipFilename;
    hash = r.zipSha256;
    url = "https://www.nvidia.com/object/vGPU-software-driver.html";
  };

  # Headless, so no settings or persistenced.
  fromRelease = nvidiaPackages.mkVgpuDriver {
    version = r.host;
    guestVersion = r.guest;
    sha256 = r.zipSha256;
    inherit (r) guestSha256;
    openSha256 = null;
    gridVersion = cfg.release;
    generalVersion = r.guest;
    useSettings = false;
    usePersistenced = false;
    inherit zipFilename;
    vgpuPatcher = null;
  };
  packaged = "${if guest then "grid" else "vgpu"}_${lib.replaceStrings [ "." ] [ "_" ] cfg.release}";
  driver = if r != null then fromRelease else nvidiaPackages.${packaged};
in
{
  options.homelab.vgpu = {
    enable = lib.mkEnableOption "NVIDIA vGPU ${if guest then "guest" else "host"} driver";

    # A key of releases.nix, or a release vgpu4nixos packages (16.2 .. 18.4).
    release = mkOption {
      type = types.str;
      default = "19.6";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = guest || r == null || r.zipSha256 != null;
        message = "vgpu: set zipSha256 for ${cfg.release} in modules/services/vgpu/releases.nix (`nix hash file --type sha256 <zip>`)";
      }
    ];

    # vGPU releases target the RHEL 10 kernel, so stay on the LTS that matches it.
    boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_6_12;

    # vgpu4nixos keeps the kernel modules in `bin`, nixpkgs' nvidia module (guests) looks for them in `mod`.
    hardware.nvidia.package = driver // { mod = driver.bin; };

    nixpkgs.config.allowUnfreePredicate = pkg: lib.hasPrefix "nvidia" (lib.getName pkg);

    system.extraDependencies = lib.optional (!guest && r != null && r.zipSha256 != null) zip;
  };
}
