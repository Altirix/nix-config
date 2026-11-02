# Installer and recovery systems for every host that boots as a Chromebook, see
# modules/hardware/chromebook/README.md. Each is built natively on aarch64 and
# cross-compiled from x86_64; the installer carries its host's system.
{ self, lib, hosts }:
let
  chromebookHosts = lib.filterAttrs (_: host: host.config.homelab.hardware.chromebook.enable) hosts;

  mkLive = name: host: buildPlatform:
    let
      platform = { nixpkgs = lib.optionalAttrs (buildPlatform != null) { inherit buildPlatform; }; };
      installed = if buildPlatform == null then host else host.extendModules { modules = [ platform ]; };
      # The live systems run on the same board, with the host's settings for it.
      inherit (host.config.homelab.hardware.chromebook) board;
      boardModules = [
        ../../modules/hardware/${board}.nix
        { homelab.hardware.${board} = host.config.homelab.hardware.${board}; }
      ];
      live = role: extra: lib.nixosSystem {
        modules = boardModules ++ [ ./${role}.nix platform { networking.hostName = "${name}-${role}"; } extra ];
      };
      recovery = live "recovery" { };
      installer = live "installer" {
        environment.etc."chromebook-system".source = installed.config.system.build.toplevel;
        environment.etc."chromebook-recovery".source = recovery.config.system.build.chromebookRecovery;
        environment.etc."chromebook-flake".source = lib.cleanSource self.outPath;
      };
    in
    { inherit installed recovery installer; };

  native = lib.mapAttrs (name: host: mkLive name host null) chromebookHosts;
  cross = lib.mapAttrs (name: host: mkLive name host "x86_64-linux") chromebookHosts;

  packages = systems: lib.concatMapAttrs (name: s: {
    "${name}-installer-image" = s.installer.config.system.build.chromebookUsbImage;
    "${name}-recovery" = s.recovery.config.system.build.chromebookRecovery;
  }) systems;
in
{
  inherit native cross;

  nixosConfigurations = lib.concatMapAttrs (name: s: {
    "${name}-installer" = s.installer;
    "${name}-recovery" = s.recovery;
  }) native;

  packages.aarch64-linux = packages native;
  # Both the installer and the systems it carries are cross-compiled.
  packages.x86_64-linux = packages cross;
}
