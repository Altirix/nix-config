{
  description = "NixOS Homelab";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    sops-nix.url = "github:Mic92/sops-nix";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }@inputs:
    let
      # Every host gets these
      commonModules = import ./modules/common.nix { inherit inputs; };
      # specialized hosts get these. 
      tagModules = {
        compute = import ./modules/compute.nix { };
      };

      # Builds one host. `name` must match its folder under hosts/.
      mkHost = { path, tags, extraModules ? [ ] }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = commonModules
            ++ (nixpkgs.lib.concatMap (tag: tagModules.${tag}) tags)
            ++ [
              ./hosts/${path}/disko.nix
              ./hosts/${path}/hardware-configuration.nix
              ./hosts/${path}/configuration.nix
              ./hosts/${path}/networking.nix
            ]
            ++ extraModules;
        };
    in
    {
      nixosConfigurations = {
        nxa = mkHost { path = "compute/nxa"; tags = [ "compute" ]; };
        nxb = mkHost { path = "compute/nxb"; tags = [ "compute" ]; };
        nxc = mkHost { path = "compute/nxc"; tags = [ "compute" ]; };
      };
    };
}