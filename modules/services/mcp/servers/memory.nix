# Knowledge graph memory, one graph shared by every client. Without an absolute MEMORY_FILE_PATH
# it writes next to its own code in the nix store. Every change rewrites the whole file in place,
# unlocked: concurrent writes can drop one, and a crash mid-write leaves a line that breaks every
# load. Back up /var/lib/private/mcp-memory (DynamicUser) to keep the graph.
{ lib, pkgs, ... }:

{
  homelab.mcp.servers.memory = {
    command = lib.mkDefault (lib.getExe pkgs.mcp-server-memory);
    port = lib.mkDefault 8107;
    environment.MEMORY_FILE_PATH = lib.mkDefault "/var/lib/mcp-memory/memory.jsonl";
  };
}
