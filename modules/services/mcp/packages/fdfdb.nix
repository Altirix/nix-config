{ lib, fetchFromGitHub, runCommand, writers, writeShellScriptBin, python3Packages }:

# NAND flash lookups from iTXTech's fdfdb (CC BY-NC-SA 4.0): the flash tables controller vendors' tools ship,
# read into one index at build time by fdfdb-mcp.py, so a table whose format changed fails the build, not a query.
let
  src = fetchFromGitHub {
    owner = "iTXTech";
    repo = "fdfdb";
    rev = "84793005815ddf140beaa1b338775673f52d3684";
    hash = "sha256-aABx6UuKQTe3Vb4W6JPd5YPQiEBmZvBXfehE7XyGDgA=";
  };

  server = writers.writePython3Bin "fdfdb-mcp-server" {
    libraries = [ python3Packages.mcp ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./fdfdb-mcp.py);

  db = runCommand "fdfdb.json" { } ''
    ${lib.getExe server} index ${src} $out
  '';
in
(writeShellScriptBin "fdfdb-mcp" ''
  exec ${lib.getExe server} serve ${db} ${src.rev}
'').overrideAttrs {
  passthru = { inherit src db; };
}
