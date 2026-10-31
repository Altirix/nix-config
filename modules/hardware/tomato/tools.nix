{ writeShellApplication, coreutils, dtc, e2fsprogs, ubootTools, util-linux, vboot-utils, zstd }:

let
  vboot = vboot-utils;
  common = builtins.readFile ./common.sh;
  slotTool = name: script: runtimeInputs: writeShellApplication {
    inherit name;
    runtimeInputs = [ coreutils util-linux vboot ] ++ runtimeInputs;
    text = common + builtins.readFile script;
  };
in
{
  pack = writeShellApplication {
    name = "tomato-pack-kernel";
    runtimeInputs = [ coreutils dtc ubootTools vboot ];
    text = builtins.replaceStrings [ "@devkeys@" ] [ "${vboot}/share/vboot/devkeys" ]
      (builtins.readFile ./pack-kernel.sh);
  };

  install = slotTool "tomato-install-kernel" ./install-kernel.sh [ ];
  markGood = slotTool "tomato-mark-good" ./mark-good.sh [ ];
  writeRecovery = slotTool "tomato-write-recovery" ./write-recovery.sh [ e2fsprogs zstd ];
}
