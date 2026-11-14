{ kicad-unstable-small, fetchFromGitLab, fetchurl, runCommand, callPackage, glslang, spirv-tools, spirv-cross, sqlite }:

# KiCad's development branch (what becomes KiCad 11), for its headless API server: `kicad-cli api-server` with
# OpenDocument, so a project's agents load one board after another (servers/kicad.nix). Pinned to the revision
# kicad-python (packages/kicad-mcp-pro.nix) is built against, their API definitions have to match: bump both
# together. Not in the binary cache, the build host compiles it (an hour or so). The libraries stay nixpkgs'
# kicad-unstable ones. Saves in its own file format, which KiCad 10 doesn't open: view with a KiCad nightly.
let
  rev = "0ef63a79e8b610a8a98c8ec8fbfc0e92b86a974d";
  fetched = fetchFromGitLab {
    owner = "kicad/code";
    repo = "kicad";
    inherit rev;
    hash = "sha256-Ew0YaWUXcSkZDCUNdx6CsGJgd2NnGla6qanOCLQYSMg=";
  };
  # The revision's own build fix, the day after: GCC 15 refuses format_as(KI_ERROR)'s deduced return type.
  explicitReturnType = fetchurl {
    url = "https://gitlab.com/kicad/code/kicad/-/commit/4b753b460125b7f8fe90f19877d16dd04d913108.diff";
    hash = "sha256-qdgZrANg5NYZ4LN5aCcBCvdNU5cvWQTj2/V3LUzUAzk=";
  };
  # nixpkgs' runtime_stock_data_path.patch anchors on GetStockDataPath's build-dir check, which KiCad since moved
  # into RunningFromBuildDir(): put that one line back as it was so the patch applies. It only matters when KiCad
  # runs from its own build tree.
  src = runCommand "kicad-source-${builtins.substring 0 10 rev}" { } ''
    cp -r ${fetched} $out
    chmod -R u+w $out
    patch -d $out -p1 < ${explicitReturnType}
    substituteInPlace $out/common/paths.cpp --replace-fail \
      'if( aRespectRunFromBuildDir && RunningFromBuildDir() )' \
      'if( aRespectRunFromBuildDir && wxGetEnv( wxT( "KICAD_RUN_FROM_BUILD_DIR" ), nullptr ) )'
  '' // { inherit rev; };
in
kicad-unstable-small.override {
  srcs = {
    kicadVersion = "2026-11-08";
    kicad = src;
  };
  # What the build has come to need since nixpkgs' recipe: its new rendering backend compiles shaders with Vulkan's
  # tools, and it links SQLite. Only KiCad itself (base.nix) gets them.
  callPackage = path: args:
    let built = callPackage path args; in
    if baseNameOf path == "base.nix" then
      built.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ [ glslang spirv-tools spirv-cross ];
        buildInputs = old.buildInputs ++ [ sqlite ];
      })
    else built;
}
