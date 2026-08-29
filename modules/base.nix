{ config, pkgs, ... }:

{
  # --- Boot ---
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # --- Locale / time ---
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";

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
}