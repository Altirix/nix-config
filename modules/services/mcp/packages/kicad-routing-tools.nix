{ lib, fetchFromGitHub, rustPlatform, stdenvNoCC, python313 }:

# KiCadRoutingTools: a grid router in Rust (grid_router, a Python extension) driven by Python CLIs that read and write
# .kicad_pcb files: the whole-board autoroute, nets a group at a time, planes, differential pairs, fan-outs, length
# and time matching, and their own DRC and connectivity checks. The KiCad server runs them as background jobs
# (kicad-mcp-pro-krt.patch). Built from source, the router included; its build_router.py downloads release binaries,
# so it isn't used. Bump `rev`, then both hashes.
let
  version = "0.24.0";

  src = fetchFromGitHub {
    owner = "drandyhaas";
    repo = "kicadroutingtools";
    rev = "f5288714aa15a1f2fba9f005027e4608ce8c2640";
    hash = "sha256-ISTKYjGzQZNAsQsUEbmJ8FG30Yo2URVcrw48BvcRopk=";
  };

  # numpy, scipy, shapely and Pillow for routing and its renders, ortools for the bus step.
  python = python313.withPackages (ps: with ps; [ numpy scipy shapely pillow ortools ]);

  router = rustPlatform.buildRustPackage {
    pname = "grid-router";
    # The crate's own version (rust_router/Cargo.toml), which the Python side checks the library against.
    version = "0.23.7";
    inherit src;
    sourceRoot = "${src.name}/rust_router";
    cargoHash = "sha256-EL/dsEcZncvOXFGBRpvhVumIVlzUZJt2/Ooil3sppeM=";
    nativeBuildInputs = [ python ];
    doCheck = false;
  };
in
stdenvNoCC.mkDerivation {
  pname = "kicad-routing-tools";
  inherit version src;

  dontConfigure = true;
  dontBuild = true;

  # The CLIs find the router as rust_router/grid_router.so next to them. Compiled ahead, as the store is read-only.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/share
    cp -r . $out/share/kicad-routing-tools
    cd $out/share/kicad-routing-tools
    install -m444 ${router}/lib/libgrid_router.so rust_router/grid_router.so
    ${python.interpreter} -m compileall -q -j0 py_router py_tools py_placer awx >/dev/null
    runHook postInstall
  '';

  passthru = { inherit python router; };

  meta = {
    description = "Autorouting, planes, fan-outs, differential pairs and length matching for KiCad boards";
    homepage = "https://github.com/drandyhaas/kicadroutingtools";
    license = lib.licenses.mit;
  };
}
