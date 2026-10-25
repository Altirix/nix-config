{ writers, python3Packages, mcp-proxy }:

# Streamable HTTP to stdio with one server process per MCP session, see mcp_session_proxy.py.
# Reuses mcp-proxy's request forwarding, only the session handling is its own.
writers.writePython3Bin "mcp-session-proxy" {
  libraries = with python3Packages; [ mcp uvicorn starlette anyio (toPythonModule mcp-proxy) ];
  flakeIgnore = [ "E501" ];
} ./mcp_session_proxy.py
