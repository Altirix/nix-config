{ lib, buildNpmPackage, fetchurl, fetchzip, nodejs, ghidra-bin, openjdk21, staticOnly ? false }:

# REA (rea-agents), built from the npm tarball: it ships the compiled dist/, the repo build needs
# turbo, tsgo and rolldown. The tarball has no lockfile, the one from the release tag matches it.
# REA checks the Ghidra and JADX versions it gets, passthru has the ones this release takes.
let
  lockfile = fetchurl {
    # Tag rea-agents-6.5.0.
    url = "https://raw.githubusercontent.com/morluto/rea/3b79af28e80785afce9f5998d8f03289402a1847/package-lock.json";
    hash = "sha256-BIIIU3LFY8mbMlGfUTOesoCtwr2D79umqO/XzUpJ6fA=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "rea-agents";
  version = "6.5.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/rea-agents/-/rea-agents-${finalAttrs.version}.tgz";
    hash = "sha256-UxcXoG6SymUaq1JpEZD5FvrARCcsAfh14ixeKTIY5pk=";
  };

  postPatch = ''
    cp ${lockfile} package-lock.json
  '';

  npmDepsHash = "sha256-EQKhS1S7Hsfjbo5GikMeAFc2HFtALsDcw6XnJATUryw=";

  inherit nodejs;
  # Already built, and prepack would rebuild it.
  dontNpmBuild = true;
  npmPackFlags = [ "--ignore-scripts" ];
  # Frida (optional) downloads its binding in an install script, REA runs without it.
  npmFlags = [ "--ignore-scripts" ];

  # staticOnly drops the modules behind the tools that run a program the caller names:
  # node-pty (capture_process_scenario), playwright-core (browser and Electron launch) and frida.
  # Those tools stay listed and fail, everything else is untouched.
  #
  # The bundled MCP SDK also speaks protocol 2026-07-28, whose requests are stateless: supergateway then gives a
  # client that discovers first no session, and the target it opened is gone by its next call. Without it,
  # clients fall back to 2025-era sessions.
  postInstall = ''
    sdk=$out/lib/node_modules/rea-agents/node_modules/@modelcontextprotocol
    grep -rlZ --include='*.js' --include='*.mjs' --include='*.cjs' 'SUPPORTED_MODERN_PROTOCOL_VERSIONS = \[FIRST_MODERN_PROTOCOL_VERSION\]' $sdk \
      | xargs -0 -r sed -i 's/SUPPORTED_MODERN_PROTOCOL_VERSIONS = \[FIRST_MODERN_PROTOCOL_VERSION\]/SUPPORTED_MODERN_PROTOCOL_VERSIONS = []/'
    if grep -rq --include='*.js' --include='*.mjs' --include='*.cjs' 'SUPPORTED_MODERN_PROTOCOL_VERSIONS = \[FIRST' $sdk; then
      echo "rea: the SDK still speaks 2026-07-28" >&2; exit 1
    fi
    grep -rq --include='*.js' --include='*.mjs' --include='*.cjs' 'SUPPORTED_MODERN_PROTOCOL_VERSIONS = \[\]' $sdk
  '' + lib.optionalString staticOnly ''
    rm -r $out/lib/node_modules/rea-agents/node_modules/{@lydell,playwright-core,frida,.bin/playwright-core}
  '';

  passthru = {
    # REA only takes Ghidra 12.1, nixpkgs has 12.0.
    ghidra = ghidra-bin.overrideAttrs {
      version = "12.1.4";
      src = fetchzip {
        url = "https://github.com/NationalSecurityAgency/ghidra/releases/download/Ghidra_12.1.4_build/ghidra_12.1.4_PUBLIC_20260921.zip";
        hash = "sha256-ZD4Vs1i7BMvrneAbAiOc7F9iBj64Rbom+PaVO//TzK8=";
      };
    };

    # The jadx-headless-mcp release REA pins, by its sha256.
    jadxMcp = fetchurl {
      url = "https://github.com/1013503897/jadx-headless-mcp/releases/download/v0.7.1/jadx-headless-mcp-0.7.1-all.jar";
      hash = "sha256-bl6s9QC2QpK/tzxJeXwZWPbuRGRuQ+hoA5rn/rVz/3U=";
    };

    # Both need a full JDK (javac), Ghidra 12.1 wants 21+.
    jdk = openjdk21;
  };

  meta = {
    description = "Reverse engineer anything, CLI and MCP server";
    homepage = "https://github.com/morluto/rea";
    license = lib.licenses.mit;
    mainProgram = "rea";
  };
})
