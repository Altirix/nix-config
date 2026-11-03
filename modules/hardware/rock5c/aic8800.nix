{ lib, stdenv, kernel, fetchFromGitHub, runCommand, xz }:

# AIC8800 USB Wi-Fi + Bluetooth (the ROCK 5C's AIC8800D80): aic_load_fw, aic8800_fdrv and
# aic_btusb out of Radxa's packaging of the vendor SDK, built against the running kernel.
#
# The driver reads its firmware with filp_open from a compiled-in path, not request_firmware,
# so that path points into the store and the blobs stay uncompressed, outside hardware.firmware.
let
  version = "5.0+git20260123.5f7be68d-10";

  src = fetchFromGitHub {
    owner = "radxa-pkg";
    repo = "aic8800";
    # Tag 5.0+git20260123.5f7be68d-10.
    rev = "e9e43ed79c50483080e9bcdfb08caeeb869d7191";
    hash = "sha256-1b7FMF32X1NkgtNEExLY4Z4v2UgrXc8lzIKyb1ls34s=";
  };

  firmware = runCommand "aic8800-firmware-${version}" {
    meta.license = lib.licenses.unfreeRedistributableFirmware;
  } ''
    mkdir -p $out/lib/firmware/aic8800_fw
    cp -r ${src}/src/USB/driver_fw/fw $out/lib/firmware/aic8800_fw/USB
  '';

  drivers = "src/USB/driver_fw/drivers";
in
stdenv.mkDerivation {
  pname = "aic8800-usb";
  version = "${version}-${kernel.version}";
  inherit src;

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ xz ];

  # The vendor sources are CRLF and Radxa's patches LF, so convert both before applying
  # debian/patches/series: kernel API fixes up to 7.3, bluez instead of bluedroid, firmware path.
  postPatch = ''
    find src/*/driver_fw/drivers -type f -exec grep -Il $'\r' {} + | xargs sed -i 's/\r$//'
    while read -r p; do
      sed 's/\r$//' debian/patches/$p | patch -p1 --no-backup-if-mismatch
    done < debian/patches/series

    substituteInPlace ${drivers}/aic8800/aic_load_fw/aicbluetooth.c ${drivers}/aic_btusb/aic_btusb.c \
      --replace-fail '"/lib/firmware/aic8800_fw' '"${firmware}/lib/firmware/aic8800_fw'
  '';

  makeFlags = kernel.commonMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "INSTALL_MOD_PATH=$(out)"
    "INSTALL_MOD_DIR=updates"
    "DEPMOD=true"
  ];

  buildPhase = ''
    runHook preBuild
    for m in aic8800 aic_btusb; do
      make "''${makeFlagsArray[@]}" $makeFlags -j$NIX_BUILD_CORES M=$PWD/${drivers}/$m modules
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    for m in aic8800 aic_btusb; do
      make "''${makeFlagsArray[@]}" $makeFlags M=$PWD/${drivers}/$m modules_install
    done
    # The .ko.xz hide the firmware path from the reference scan, keep it in the closure.
    mkdir -p $out/nix-support
    echo ${firmware} > $out/nix-support/aic8800-firmware
    runHook postInstall
  '';

  passthru = { inherit firmware; };

  meta = {
    description = "AIC8800 USB Wi-Fi and Bluetooth drivers";
    homepage = "https://github.com/radxa-pkg/aic8800";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
