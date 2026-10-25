# The sandbox every MCP server's unit gets (homelab.mcp.servers, REA's gateway), merged into its serviceConfig.
{
  ProtectSystem = "strict";
  ProtectHome = true;
  PrivateTmp = true;
  PrivateDevices = true;
  # Each server only sees its own processes.
  ProtectProc = "invisible";
  NoNewPrivileges = true;
  CapabilityBoundingSet = "";
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectKernelLogs = true;
  ProtectControlGroups = true;
  ProtectClock = true;
  ProtectHostname = true;
  LockPersonality = true;
  RestrictNamespaces = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  SystemCallArchitectures = "native";
  RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
}
