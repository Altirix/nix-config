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
      mkHost = category: name: extraModules:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = commonModules ++ [
            ./hosts/${category}/${name}/disko.nix
            ./hosts/${category}/${name}/hardware-configuration.nix
            ./hosts/${category}/${name}/configuration.nix
            ./hosts/${category}/${name}/networking.nix
          ] ++ extraModules;
        };
    in
    {
      nixosConfigurations = {
        nxa = mkHost "compute" "nxa" [ ];
        nxb = mkHost "compute" "nxb" [ ];
        nxc = mkHost "compute" "nxc" [ ];
      };
    };
}