{ inputs, lib, pkgs, ... }:

# Every host gets this: the generic building blocks and the baseline config.
# Host-type modules (compute.nix, storage.nix, virtual.nix, edge.nix) add their own blocks on top,
# a host imports one of them.
{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    ./system/ssh.nix
    ./system/secrets.nix
    ./disks/disko.nix
    ./system/boot.nix
    ./networking/lan.nix
    ./disks/zfs.nix
    ./hardware/rock5c.nix
  ];

  # --- Boot ---
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  # --- Locale / time ---
  time.timeZone = lib.mkDefault "Europe/London";
  i18n.defaultLocale = lib.mkDefault "en_GB.UTF-8";

  # --- Baseline packages ---
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    curl
    dig
    smartmontools
  ];

  nixpkgs.config.allowUnfree = false;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # --- Users ---
  users.mutableUsers = false;

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  security.sudo.wheelNeedsPassword = false;

  # --- Secrets ---
  sops.secrets = {
    "common-hello" = {
      sopsFile = ../secrets/common.yaml;
      key = "hello";
    };
  };
}
