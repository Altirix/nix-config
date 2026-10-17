{ config, lib, pkgs, ... }:

# Converts http(s):, file: and data: URIs (HTML, PDF, DOCX, PPTX, XLSX, ...) to markdown. Its own
# --http serves stateless streamable HTTP on /mcp and SSE on /sse, so no mcp-proxy.
# file: reads what the dynamic user can: the store and world-readable /etc, not /home or
# /run/secrets (root 0400), and http: reaches anything on the labs network. Audio is sent to
# Google's speech API for transcription. Upstream hard-codes Starlette debug, so a crash returns a
# traceback to the client.
let
  cfg = config.homelab.mcp.servers.markitdown;
in
{
  homelab.mcp.servers.markitdown = {
    command = lib.mkDefault (lib.getExe pkgs.markitdown-mcp);
    args = lib.mkDefault [ "--http" "--host" "0.0.0.0" "--port" (toString cfg.port) ];
    transport = lib.mkDefault "http";
    port = lib.mkDefault 8109;
  };
}
