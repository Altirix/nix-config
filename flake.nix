{
  description = "NixOS Homelab";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Its pinned nixpkgs has an older gcc than the kernel was built with, the modules wouldn't compile.
    vgpu4nixos = {
      url = "github:mrzenc/vgpu4nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fastapi-dls-nixos = {
      url = "github:mrzenc/fastapi-dls-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      lib = nixpkgs.lib;

      dirs = path: lib.attrNames (lib.filterAttrs
        (name: type: type == "directory" && !lib.hasPrefix "_" name)
        (builtins.readDir path));

      # Every hosts/<group>/<name>/default.nix is a host, the group is only for layout.
      # Hosts with an empty default.nix are placeholders and skipped.
      isHost = group: name:
        let entry = ./hosts/${group}/${name}/default.nix;
        in builtins.pathExists entry && builtins.readFile entry != "";

      hosts = lib.concatMap (group:
        map (name: { inherit group name; }) (lib.filter (isHost group) (dirs ./hosts/${group})))
        (dirs ./hosts);

      # Every host gets modules/default.nix, the host directory imports its type (compute.nix, virtual.nix ...).
      mkHost = { group, name }:
        let
          dir = ./hosts/${group}/${name};
        in
        lib.nixosSystem {
          # `nodes` lets a host read the config of the other hosts
          specialArgs = { inherit inputs; nodes = self.nixosConfigurations; };
          modules = [
            ./modules
            dir
            {
              networking.hostName = name;
              # ZFS won't import pools written under another hostId, pin it in the host before renaming one.
              networking.hostId = lib.mkDefault (builtins.substring 0 8 (builtins.hashString "sha256" name));
              sops.defaultSopsFile = lib.mkIf (builtins.pathExists (dir + "/secrets.yaml")) (dir + "/secrets.yaml");
            }
          ];
        };
      # Chromebook boards booting from stock Depthcharge, see modules/hardware/chromebook/README.md.
      # Each gets a USB installer carrying its host's system and a recovery system, natively
      # on aarch64 or cross-compiled from x86_64.
      # `board` is the modules enabling the board in the live systems; the host enables it itself.
      chromebooks.tomato = {
        host = "colluvium";
        board = [ ./modules/hardware/tomato.nix { homelab.hardware.tomato = { enable = true; wifi = true; }; } ];
      };
      chromebook = name: { host, board }: buildPlatform:
        let
          platform = { nixpkgs = lib.optionalAttrs (buildPlatform != null) { inherit buildPlatform; }; };
          installed = if buildPlatform == null then self.nixosConfigurations.${host}
            else self.nixosConfigurations.${host}.extendModules { modules = [ platform ]; };
          live = role: extra: lib.nixosSystem {
            modules = board ++ [ ./installers/chromebook/${role}.nix platform
              { networking.hostName = "${name}-${role}"; } extra ];
          };
          recovery = live "recovery" { };
          installer = live "installer" {
            environment.etc."chromebook-system".source = installed.config.system.build.toplevel;
            environment.etc."chromebook-recovery".source = recovery.config.system.build.chromebookRecovery;
            environment.etc."chromebook-flake".source = lib.cleanSource self.outPath;
          };
        in
        { inherit installed recovery installer; };
      chromebooksNative = lib.mapAttrs (name: cb: chromebook name cb null) chromebooks;
      chromebooksCross = lib.mapAttrs (name: cb: chromebook name cb "x86_64-linux") chromebooks;
      chromebookPackages = systems: lib.concatMapAttrs (name: cb: {
        "${name}-installer-image" = cb.installer.config.system.build.chromebookUsbImage;
        "${name}-recovery" = cb.recovery.config.system.build.chromebookRecovery;
      }) systems;
    in
    {
      nixosConfigurations = lib.listToAttrs (map (host: lib.nameValuePair host.name (mkHost host)) hosts)
        // lib.concatMapAttrs (name: cb: {
          "${name}-installer" = cb.installer;
          "${name}-recovery" = cb.recovery;
        }) chromebooksNative;

      packages.aarch64-linux = chromebookPackages chromebooksNative;
      # Both the installer and the systems it carries are cross-compiled.
      packages.x86_64-linux = chromebookPackages chromebooksCross;

      checks.x86_64-linux.chromebook = import ./tests/chromebook.nix { pkgs = nixpkgs.legacyPackages.x86_64-linux; };
      checks.x86_64-linux.tomato = import ./tests/tomato.nix {
        inherit self;
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        cross = chromebooksCross.tomato;
      };

      # VM tests in tests/, `nix build .#checks.x86_64-linux.<name>`.
      checks.x86_64-linux.chromebook-slots = nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest (import ./tests/chromebook-slots.nix);
      checks.x86_64-linux.mcp = nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest (import ./tests/mcp.nix self);
      checks.x86_64-linux.rea = nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest (import ./tests/rea.nix self);
    };
}
