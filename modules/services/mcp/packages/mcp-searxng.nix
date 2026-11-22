{ lib, buildNpmPackage, fetchurl, nodejs_24 }:

# Web search through a SearXNG instance, and a page reader (web_url_read). Built from the npm tarball (compiled
# dist/), which has no lockfile; the one from the release commit matches its dependencies.
let
  lockfile = fetchurl {
    # Release 2.11.0.
    url = "https://raw.githubusercontent.com/ihor-sokoliuk/mcp-searxng/8b05e79e6e5e935582acbc13e8b34087add0adbb/package-lock.json";
    hash = "sha256-GXLPXhA7ObnohknqvfZmP9/LBa4sGuef1BgtTlnUXYQ=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "mcp-searxng";
  version = "2.11.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/mcp-searxng/-/mcp-searxng-${finalAttrs.version}.tgz";
    hash = "sha256-Aj5jzLRwA0oGDR8rhGzTwz0S0WJAKQEgiPbLd/47Va8=";
  };

  postPatch = ''
    cp ${lockfile} package-lock.json
  '';

  npmDepsHash = "sha256-javCwS77DHqRyAcUWlZhsgm84PqS5x/4ovUI+v4OriY=";

  nodejs = nodejs_24;
  # Already built, and prepack would rebuild it.
  dontNpmBuild = true;
  npmPackFlags = [ "--ignore-scripts" ];
  npmFlags = [ "--ignore-scripts" ];

  meta = {
    description = "MCP server for SearXNG";
    homepage = "https://github.com/ihor-sokoliuk/mcp-searxng";
    license = lib.licenses.mit;
    mainProgram = "mcp-searxng";
  };
})
