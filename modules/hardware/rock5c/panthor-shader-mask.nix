{ stdenv, kernel, xz }:

# The in-tree panthor module with patches/panthor-shader-mask.patch, built against the
# running kernel so only panthor.ko is rebuilt, not the whole kernel.
stdenv.mkDerivation {
  pname = "panthor-shader-mask";
  inherit (kernel) version src;

  patches = [ ./patches/panthor-shader-mask.patch ];

  nativeBuildInputs = kernel.moduleBuildDependencies ++ [ xz ];

  makeFlags = kernel.commonMakeFlags ++ [
    "-C"
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
    "INSTALL_MOD_PATH=$(out)"
    "INSTALL_MOD_DIR=updates"
    "DEPMOD=true"
  ];

  preBuild = ''
    makeFlagsArray+=(M=$PWD/drivers/gpu/drm/panthor)
  '';

  buildFlags = [ "modules" ];
  installTargets = [ "modules_install" ];

  # Ahead of kernel/drivers/gpu/drm/panthor when NixOS runs depmod over all modules.
  postInstall = ''
    mkdir -p $out/etc/depmod.d
    echo "override panthor * updates" > $out/etc/depmod.d/panthor.conf
  '';
}
