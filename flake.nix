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
      commonModules = [ ./modules/common.nix ];

      # Map tag names directly to lists of file paths
      tagModules = {
        compute = [ ./modules/compute.nix ];
      };

      # Builds one host. `path` determines the directory under hosts/
      mkHost = { path, tags ? [ ], extraModules ? [ ] }:
        let 
          hostName = baseNameOf path; 
          hostId = builtins.substring 0 8 (builtins.hashString "sha256" hostName);
        in
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          # specialArgs passes `inputs` to modules automatically
          specialArgs = { inherit inputs; };
          modules = commonModules
            ++ (nixpkgs.lib.concatMap (tag: tagModules.${tag}) tags)
            ++ [
              ./hosts/${path}/disko.nix
              ./hosts/${path}/hardware-configuration.nix
              ./hosts/${path}/configuration.nix
              ./hosts/${path}/networking.nix
              { networking.hostName = hostName; }
              { networking.hostId = hostId; }
            ]
            ++ extraModules;
        };
    in
    {
      nixosConfigurations = {
        andromeda = mkHost { 
          path = "compute/andromeda"; 
          tags = [ "compute" ]; 
          extraModules = [ ./modules/extra/grub-mirror-boot.nix ];};
        nxb = mkHost { path = "compute/nxb"; tags = [ "compute" ]; };
        nxc = mkHost { path = "compute/nxc"; tags = [ "compute" ]; };
      };
    };
}