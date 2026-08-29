{
  description = "NixOS Homelab";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, disko, ... }@inputs:
    let
      # Every host gets these, always - add/remove once here, applies everywhere.
      commonModules = import ./modules/common.nix { inherit disko; };

      # Builds one host. `name` must match its folder under hosts/.
      mkHost = name: extraModules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = commonModules ++ [
            ./hosts/${name}/disko.nix
            ./hosts/${name}/hardware-configuration.nix
            ./hosts/${name}/configuration.nix
            ./hosts/${name}/networking.nix
          ] ++ extraModules;
        };
    in
    {
      nixosConfigurations = {
        nxa = mkHost "nxa" [ ];
        nxb = mkHost "nxb" [ ];
        nxc = mkHost "nxc" [ ];
      };
    };
}