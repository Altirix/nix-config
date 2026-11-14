{ kicad-unstable-small, fetchFromGitLab, fetchurl, callPackage, glslang, spirv-tools, spirv-cross, sqlite }:

# KiCad's development branch (what becomes KiCad 11), for its headless API server: `kicad-cli api-server` with
# OpenDocument, so a project's agents load one board after another (servers/kicad.nix). Pinned to the revision
# kicad-python (packages/kicad-mcp-pro.nix) is built against, their API definitions have to match: bump both
# together. Not in the binary cache, the build host compiles it (an hour or so). The libraries stay nixpkgs'
# kicad-unstable ones. Saves in its own file format, which KiCad 10 doesn't open: view with a KiCad nightly.
kicad-unstable-small.override {
  srcs = {
    kicadVersion = "2026-11-08";
    kicad = fetchFromGitLab {
      owner = "kicad/code";
      repo = "kicad";
      rev = "0ef63a79e8b610a8a98c8ec8fbfc0e92b86a974d";
      hash = "sha256-Ew0YaWUXcSkZDCUNdx6CsGJgd2NnGla6qanOCLQYSMg=";
    };
  };
  # KiCad itself (base.nix) as nixpkgs' recipe from May builds it, brought up to this revision. What its build has
  # come to need: its new rendering backend compiles shaders with Vulkan's tools, and it links SQLite. Its patches,
  # in place of nixpkgs': the stock data path one rebased (the function it patches moved), writable.patch dropped
  # (KiCad makes copied template files writable itself now), and the revision's own next-day build fix (GCC 15
  # refuses format_as(KI_ERROR)'s deduced return type, upstream 4b753b46).
  callPackage = path: args:
    let built = callPackage path args; in
    if baseNameOf path == "base.nix" then
      built.overrideAttrs (old: {
        patches = [
          ./kicad-master-stock-data-path.patch
          (fetchurl {
            url = "https://gitlab.com/kicad/code/kicad/-/commit/4b753b460125b7f8fe90f19877d16dd04d913108.diff";
            hash = "sha256-qdgZrANg5NYZ4LN5aCcBCvdNU5cvWQTj2/V3LUzUAzk=";
          })
        ];
        nativeBuildInputs = old.nativeBuildInputs ++ [ glslang spirv-tools spirv-cross ];
        buildInputs = old.buildInputs ++ [ sqlite ];
      })
    else built;
}
