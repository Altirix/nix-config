{ lib, buildNpmPackage, fetchurl, nodejs_24 }:

# Paperless-NGX over MCP: documents, tags, correspondents, document types, custom fields. Built from the npm
# tarball (compiled build/), which has no lockfile; the one from the release commit matches its dependencies.
let
  lockfile = fetchurl {
    # Release 2.2.1.
    url = "https://raw.githubusercontent.com/baruchiro/paperless-mcp/5bbd6488119705d46b5850c239a655736c93bd2f/package-lock.json";
    hash = "sha256-PoBONyvEVnbTburEoq6m9L32i04Z2iO5UGYM+CDs/Wk=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "paperless-mcp";
  version = "2.2.1";

  src = fetchurl {
    url = "https://registry.npmjs.org/@baruchiro/paperless-mcp/-/paperless-mcp-${finalAttrs.version}.tgz";
    hash = "sha256-F2WQEenKpZS2FiqPCCQjpI+8ohywht0tKoHdQyplMQM=";
  };

  postPatch = ''
    cp ${lockfile} package-lock.json
  '';

  npmDepsHash = "sha256-ek8p3FmcM24RdpFXEAbJ4RFJDcA8j9bpmNfPXF3wGjc=";

  nodejs = nodejs_24;
  # Already built, and prepack would rebuild it.
  dontNpmBuild = true;
  npmPackFlags = [ "--ignore-scripts" ];
  npmFlags = [ "--ignore-scripts" ];

  meta = {
    description = "MCP server for Paperless-NGX";
    homepage = "https://github.com/baruchiro/paperless-mcp";
    license = lib.licenses.isc;
    mainProgram = "paperless-mcp";
  };
})
