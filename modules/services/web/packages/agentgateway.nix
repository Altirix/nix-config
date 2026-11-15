{ lib, stdenvNoCC, fetchurl }:

# agentgateway, an MCP-aware proxy (modules/services/web, `audit`). Upstream's release binary, statically linked:
# building it means its Rust workspace and the admin UI's npm build, for a binary that runs as is.
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "agentgateway";
  version = "1.7.0";

  src = fetchurl {
    url = "https://github.com/agentgateway/agentgateway/releases/download/v${finalAttrs.version}/agentgateway-linux-amd64";
    hash = "sha256-Gy/AGi3inKETu7Yli1yuex6zxyQHHAnWh6RJEy8vQvg=";
  };

  dontUnpack = true;
  installPhase = ''
    install -Dm755 $src $out/bin/agentgateway
  '';

  meta = {
    description = "Proxy for agentic traffic: MCP, A2A and LLMs";
    homepage = "https://agentgateway.dev";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "agentgateway";
  };
})
