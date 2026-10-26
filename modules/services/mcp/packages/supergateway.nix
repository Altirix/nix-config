{ lib, buildNpmPackage, fetchurl, nodejs }:

# Supergateway, stdio MCP servers over Streamable HTTP. Built from the npm tarball (compiled dist/), the
# tarball has no lockfile, the one from the release commit matches it.
let
  lockfile = fetchurl {
    # Release 4.2.1.
    url = "https://raw.githubusercontent.com/supercorp-ai/supergateway/a78bd90804d3080e8268961949f22575b34826f0/package-lock.json";
    hash = "sha256-9gBnHXf2rJYnnuQYOBxAyLKlFTdpcsFcDrzTcr/KuUM=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "supergateway";
  version = "4.2.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/supergateway/-/supergateway-${finalAttrs.version}.tgz";
    hash = "sha256-UNqY2n0moM8yyXhmlcbHMavRSvi0jlLLwDzUXIS7Tuo=";
  };

  postPatch = ''
    cp ${lockfile} package-lock.json
  '';

  npmDepsHash = "sha256-5QS2If2js7vOn68c6I2dAXNIuzdtr4NV6NMhAG/20Eo=";

  inherit nodejs;
  # Already built, and prepack would rebuild it.
  dontNpmBuild = true;
  npmPackFlags = [ "--ignore-scripts" ];
  npmFlags = [ "--ignore-scripts" ];

  meta = {
    description = "Run MCP stdio servers over SSE, WebSockets or Streamable HTTP";
    homepage = "https://github.com/supercorp-ai/supergateway";
    license = lib.licenses.mit;
    mainProgram = "supergateway";
  };
})
