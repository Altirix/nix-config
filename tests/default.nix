# Flake checks, `nix build .#checks.x86_64-linux.<name>`. VM tests need KVM.
{ self, pkgs }:
let
  vmTest = test: pkgs.testers.runNixOSTest test;
in
{
  mcp = vmTest (import ./mcp.nix self);
  rea = vmTest (import ./rea.nix self);
}
