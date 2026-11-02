# Installer and recovery systems for each Chromebook board, see
# modules/hardware/chromebook/README.md. Each board gets them natively on aarch64
# and cross-compiled from x86_64; the installer carries its host's system.
{ self, lib }:
let
  # Board -> the host it installs. The board's module is modules/hardware/<board>.nix,
  # and the live systems take the host's settings for it, so they always match.
  boards.tomato = "colluvium";

  mkBoard = board: host: buildPlatform:
    let
      platform = { nixpkgs = lib.optionalAttrs (buildPlatform != null) { inherit buildPlatform; }; };
      native = self.nixosConfigurations.${host};
      installed = if buildPlatform == null then native else native.extendModules { modules = [ platform ]; };
      boardModules = [
        ../../modules/hardware/${board}.nix
        { homelab.hardware.${board} = native.config.homelab.hardware.${board}; }
      ];
      live = role: extra: lib.nixosSystem {
        modules = boardModules ++ [ ./${role}.nix platform { networking.hostName = "${board}-${role}"; } extra ];
      };
      recovery = live "recovery" { };
      installer = live "installer" {
        environment.etc."chromebook-system".source = installed.config.system.build.toplevel;
        environment.etc."chromebook-recovery".source = recovery.config.system.build.chromebookRecovery;
        environment.etc."chromebook-flake".source = lib.cleanSource self.outPath;
      };
    in
    { inherit installed recovery installer; };

  native = lib.mapAttrs (board: host: mkBoard board host null) boards;
  cross = lib.mapAttrs (board: host: mkBoard board host "x86_64-linux") boards;

  packages = systems: lib.concatMapAttrs (board: s: {
    "${board}-installer-image" = s.installer.config.system.build.chromebookUsbImage;
    "${board}-recovery" = s.recovery.config.system.build.chromebookRecovery;
  }) systems;
in
{
  inherit native cross;

  nixosConfigurations = lib.concatMapAttrs (board: s: {
    "${board}-installer" = s.installer;
    "${board}-recovery" = s.recovery;
  }) native;

  packages.aarch64-linux = packages native;
  # Both the installer and the systems it carries are cross-compiled.
  packages.x86_64-linux = packages cross;
}
