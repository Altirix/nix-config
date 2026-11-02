# Flake checks, `nix build .#checks.x86_64-linux.<name>`. VM tests need KVM.
{ self, pkgs, chromebooks }:
let
  vmTest = test: pkgs.testers.runNixOSTest test;
in
{
  chromebook = import ./chromebook.nix { inherit pkgs; };
  chromebook-slots = vmTest ./chromebook-slots.nix;
  mcp = vmTest (import ./mcp.nix self);
  rea = vmTest (import ./rea.nix self);
}
