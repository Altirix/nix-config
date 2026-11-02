{ pkgs, ... }:

# Partitioning and A/B + recovery slot handling on a virtual disk, with
# Depthcharge's kern_guid faked through CHROMEBOOK_CMDLINE. Does not emulate Depthcharge.
let
  fixtures = import ./chromebook-fixture.nix { inherit pkgs; };
in
{
  name = "chromebook-slots";

  nodes.machine = {
    virtualisation.emptyDiskImages = [ 5120 ];
    environment.systemPackages = with fixtures.tools; [ pack install markGood installRecovery partition waitOnline ]
      ++ [ pkgs.vboot-utils pkgs.e2fsprogs ];
  };

  # The script reads these values; the rest is in chromebook-slots.py.
  testScript = ''
    layout = ${builtins.toJSON (import ../modules/hardware/chromebook/layout.nix)}
    system = "${fixtures.system}"
    recovery = "${fixtures.recovery}"
    devkeys = "${pkgs.vboot-utils}/share/vboot/devkeys"
  '' + builtins.readFile ./chromebook-slots.py;
}
