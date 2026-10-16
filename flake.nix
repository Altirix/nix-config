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
    in
    {
      nixosConfigurations = lib.listToAttrs (map (host: lib.nameValuePair host.name (mkHost host)) hosts);
    };
}
