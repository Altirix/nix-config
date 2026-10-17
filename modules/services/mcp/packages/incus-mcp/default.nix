{ writers, python3Packages }:

# Read-only Incus MCP server, see incus_mcp.py. Only ever sends GET.
writers.writePython3Bin "incus-mcp" {
  libraries = [ python3Packages.mcp ];
  flakeIgnore = [ "E501" ];
} ./incus_mcp.py
