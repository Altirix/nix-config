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
      # Tomato installer and recovery systems, native on aarch64 or cross-compiled from x86_64.
      # The installer carries the Colluvium and recovery systems for an offline first installation.
      tomato = buildPlatform:
        let
          cross = { nixpkgs = lib.optionalAttrs (buildPlatform != null) { inherit buildPlatform; }; };
          colluvium = if buildPlatform == null then self.nixosConfigurations.colluvium
            else self.nixosConfigurations.colluvium.extendModules { modules = [ cross ]; };
          recovery = lib.nixosSystem { modules = [ ./installers/tomato-recovery.nix cross ]; };
          installer = lib.nixosSystem {
            modules = [
              ./installers/tomato.nix
              cross
              {
                environment.etc."tomato-system".source = colluvium.config.system.build.toplevel;
                environment.etc."tomato-recovery".source = recovery.config.system.build.tomatoRecovery;
                environment.etc."tomato-flake".source = lib.cleanSource self.outPath;
              }
            ];
          };
        in
        { inherit colluvium recovery installer; };
      tomatoNative = tomato null;
      tomatoCross = tomato "x86_64-linux";
    in
    {
      nixosConfigurations = lib.listToAttrs (map (host: lib.nameValuePair host.name (mkHost host)) hosts) // {
        tomato-installer = tomatoNative.installer;
        tomato-recovery = tomatoNative.recovery;
      };

      packages.aarch64-linux = {
        tomato-installer-image = tomatoNative.installer.config.system.build.tomatoDepthchargeImage;
        tomato-recovery = tomatoNative.recovery.config.system.build.tomatoRecovery;
      };
      # Both the installer and the systems it carries are cross-compiled.
      packages.x86_64-linux = {
        tomato-installer-image = tomatoCross.installer.config.system.build.tomatoDepthchargeImage;
        tomato-recovery = tomatoCross.recovery.config.system.build.tomatoRecovery;
      };

      checks.x86_64-linux.tomato = import ./tests/tomato.nix {
        inherit self;
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        cross = {
          installed = tomatoCross.colluvium.config;
          installer = tomatoCross.installer.config;
          recovery = tomatoCross.recovery.config;
          installedPkgs = tomatoCross.colluvium.pkgs;
          installerPkgs = tomatoCross.installer.pkgs;
        };
      };

      # VM tests in tests/, `nix build .#checks.x86_64-linux.<name>`.
      checks.x86_64-linux.tomato-slots = nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest (import ./tests/tomato-slots.nix);
      checks.x86_64-linux.mcp = nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest (import ./tests/mcp.nix self);
      checks.x86_64-linux.rea = nixpkgs.legacyPackages.x86_64-linux.testers.runNixOSTest (import ./tests/rea.nix self);
    };
}
