{ lib, buildNpmPackage, fetchurl, nodejs_24, python3 }:

# JLCPCB/LCSC parts over MCP: a local SQLite catalog built from yaqwsx/jlcparts (JLC assembly stock as of its last
# build), with live LCSC stock, price breaks and datasheets per query. Built from the npm tarball (compiled dist/),
# which has no lockfile; the one from the release commit matches its dependencies.
let
  lockfile = fetchurl {
    # Release 0.5.0.
    url = "https://raw.githubusercontent.com/Eyalm321/jlcpcb-mcp/f8bc76a1b4918a50eb2cde9742aa58d4ccf661fc/package-lock.json";
    hash = "sha256-bhMEEt3rSoEdEB/zihjmMjqYAGwx8o6bacnipH/1dR8=";
  };
in
buildNpmPackage (finalAttrs: {
  pname = "jlcpcb-mcp";
  version = "0.5.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/jlcpcb-mcp/-/jlcpcb-mcp-${finalAttrs.version}.tgz";
    hash = "sha256-QO2yUEi4Cqk0LRUC5665vnGhrzrYpzHe+5fq4Ghdulc=";
  };

  # Its official API, PCB and 3D-printing tools (orders among them) are only listed with JLCPCB API credentials.
  patches = [ ./jlcpcb-mcp-official-tools.patch ];

  postPatch = ''
    cp ${lockfile} package-lock.json
  '';

  npmDepsHash = "sha256-N1KEJwlbde1ma9munum2upQ7d3KYTa8vMbkdqwePS+g=";

  nodejs = nodejs_24;
  # Already built, and prepack would rebuild it.
  dontNpmBuild = true;
  npmPackFlags = [ "--ignore-scripts" ];
  npmFlags = [ "--ignore-scripts" ];

  # better-sqlite3 is native, and its install script would download a prebuilt binary: build it from its bundled
  # SQLite instead.
  nativeBuildInputs = [ python3 ];
  postConfigure = ''
    (cd node_modules/better-sqlite3 && npm run build-release --offline)
  '';

  # jlcpcb-mcp-build-catalog builds a catalog at JLCPCB_DATABASE_PATH apart from the running server
  # (servers/jlcpcb.nix), which would otherwise delete its own to rebuild it.
  postInstall = ''
    cat > $out/lib/node_modules/jlcpcb-mcp/dist/build-catalog.js <<'JS'
    #!/usr/bin/env node
    require("./database.js").dbManager.downloadDatabase().catch((err) => { console.error(err); process.exit(1); });
    JS
    chmod +x $out/lib/node_modules/jlcpcb-mcp/dist/build-catalog.js
    ln -s ../lib/node_modules/jlcpcb-mcp/dist/build-catalog.js $out/bin/jlcpcb-mcp-build-catalog
  '';

  meta = {
    description = "MCP server for JLCPCB/LCSC components";
    homepage = "https://github.com/Eyalm321/jlcpcb-mcp";
    license = lib.licenses.mit;
    mainProgram = "jlcpcb-mcp";
  };
})
