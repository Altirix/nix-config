{ writeShellApplication, coreutils, dtc, ubootTools, vboot-utils, util-linux }:

let
  vboot = vboot-utils;
in
{
  pack = writeShellApplication {
    name = "tomato-pack-kernel";
    runtimeInputs = [ coreutils dtc ubootTools vboot ];
    text = builtins.replaceStrings [ "@devkeys@" ] [ "${vboot}/share/vboot/devkeys" ]
      (builtins.readFile ./pack-kernel.sh);
  };

  install = writeShellApplication {
    name = "tomato-install-kernel";
    runtimeInputs = [ coreutils util-linux vboot ];
    text = builtins.readFile ./install-kernel.sh;
  };
}
