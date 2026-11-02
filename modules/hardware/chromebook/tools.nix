# Scripts for booting NixOS from stock Depthcharge. `dtbs` is the board's set of
# device trees, relative to the system's dtbs/ directory, all packed into the FIT.
{ lib, writeShellApplication, coreutils, dtc, e2fsprogs, gptfdisk, iproute2, systemd, ubootTools
, util-linux, vboot-utils, zstd, dtbs ? [ ] }:

let
  layout = import ./layout.nix;
  vboot = vboot-utils;
  substitute = builtins.replaceStrings
    [ "@kernelA@" "@kernelB@" "@kernelR@" "@recovery@" "@root@" "@kernelSizeMiB@" "@recoverySizeMiB@" "@devkeys@" "@dtbs@" ]
    [ layout.kernelA layout.kernelB layout.kernelR layout.recovery layout.root
      (toString layout.kernelSizeMiB) (toString layout.recoverySizeMiB)
      "${vboot}/share/vboot/devkeys" (lib.escapeShellArgs dtbs) ];
  tool = name: scripts: runtimeInputs: writeShellApplication {
    inherit name runtimeInputs;
    text = substitute (lib.concatMapStrings builtins.readFile scripts);
    # common.sh is a shared library: each script calls only some of its functions.
    excludeShellChecks = [ "SC2329" ];
  };
  slotInputs = [ coreutils util-linux vboot ];
  pack = tool "chromebook-pack-kernel" [ ./pack-kernel.sh ] [ coreutils dtc ubootTools vboot ];
in
{
  inherit pack;
  install = tool "chromebook-install-kernel" [ ./common.sh ./install-kernel.sh ] (slotInputs ++ [ pack ]);
  markGood = tool "chromebook-mark-good" [ ./common.sh ./mark-good.sh ] slotInputs;
  installRecovery = tool "chromebook-install-recovery" [ ./common.sh ./write-recovery.sh ] (slotInputs ++ [ e2fsprogs zstd ]);
  partition = tool "chromebook-partition" [ ./partition.sh ] [ coreutils util-linux gptfdisk systemd ];
  waitOnline = tool "chromebook-wait-online" [ ./wait-online.sh ] [ coreutils iproute2 ];
}
