{ lib, buildNpmPackage, fetchurl, nodejs_24 }:

# DigiKey's Product Information v4 API over MCP: search, details, quantity pricing, substitutes, media. Built from the
# npm tarball (compiled dist/), which has no lockfile; the one from the release commit matches its dependencies.
let
  lockfile = fetchurl {
    # Release 0.1.0.
    url = "https://raw.githubusercontent.com/darkdragonsastro/digikey-mcp/cc2e2c7312cf78caeda47bbc5fb8c67c13b501d5/package-lock.json";
    hash = "sha256-uZ9sujfjwIkPe1ALGEZvNJ56kCany8NBVhWtE4F81o4=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "digikey-mcp";
  version = "0.1.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@darkdragonsastro/digikey-mcp/-/digikey-mcp-${finalAttrs.version}.tgz";
    hash = "sha256-8I47mBkDZtQDctGo3O0ckBsTwLWpuq2EGepY5qTZVUU=";
  };

  # Prices and stock for the site set in the environment (UK, GBP) rather than always US dollars.
  patches = [ ./digikey-mcp-locale.patch ];

  postPatch = ''
    cp ${lockfile} package-lock.json
  '';

  npmDepsHash = "sha256-d8iEcO+7tCEd63y86QQUWL59aS/2DPdOcPfOmYBZF8c=";

  nodejs = nodejs_24;
  # Already built, and prepack would rebuild it.
  dontNpmBuild = true;
  npmPackFlags = [ "--ignore-scripts" ];
  npmFlags = [ "--ignore-scripts" ];

  meta = {
    description = "MCP server for the DigiKey Product Information v4 API";
    homepage = "https://github.com/darkdragonsastro/digikey-mcp";
    license = lib.licenses.isc;
    mainProgram = "digikey-mcp";
  };
})
