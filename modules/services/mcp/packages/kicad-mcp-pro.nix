{ lib, python313, fetchPypi, fetchFromGitLab, kicad }:

# KiCad MCP Pro: schematic and board reading and editing, KiCad's own ERC/DRC, DFM, BOM and manufacturing exports
# (kicad-cli, on the server's PATH). Newer than nixpkgs on several fronts, so it gets a Python package set of its
# own: the MCP SDK 2.x (with mcp-types, httpx2 and httpcore2 to match), kicad-python from git (built against `kicad`,
# the KiCad it talks to) and kicad-sch-api. Nothing outside this server sees them. Tests are off for the
# overridden ones, upstream runs them; check `kicad-mcp-pro --help` after a bump.
let
  pypi = pname: version: hash: fetchPypi { inherit pname version hash; };

  python = python313.override {
    self = python;
    packageOverrides = pyself: pysuper: {
      httpcore2 = pysuper.httpcore2.overridePythonAttrs (old: {
        version = "2.16.0";
        src = pypi "httpcore2" "2.16.0" "sha256-xyzQQTVjsX4c2DVGd9/4h0ZvjsJVFnl1npMSZTRChkM=";
        # Only reads its version, which the build sets.
        postPatch = ''
          substituteInPlace pyproject.toml --replace-fail '"uv-dynamic-versioning>=0.14.1"' '"uv-dynamic-versioning"'
        '';
        preCheck = "";
        doCheck = false;
      });

      httpx2 = pysuper.httpx2.overridePythonAttrs (old: {
        version = "2.16.0";
        src = pypi "httpx2" "2.16.0" "sha256-DVTJgSjo8v9/u94Pyow1nl8DLt6qqsRDzbfzH2hbzX8=";
        postPatch = ''
          substituteInPlace pyproject.toml --replace-fail '"uv-dynamic-versioning>=0.14.1"' '"uv-dynamic-versioning"'
        '';
        preCheck = "";
        dependencies = old.dependencies ++ [ pyself.truststore ];
        pythonRelaxDeps = [ "idna" ];
        doCheck = false;
      });

      mcp-types = pyself.buildPythonPackage {
        pname = "mcp-types";
        version = "2.3.0";
        pyproject = true;
        src = pypi "mcp_types" "2.3.0" "sha256-0eRlSe2zXuGalJQPzubRrd1+WJq36pLdqD9dhHgfw2I=";
        build-system = [ pyself.hatchling pyself.uv-dynamic-versioning ];
        dependencies = [ pyself.pydantic pyself.typing-extensions ];
        pythonImportsCheck = [ "mcp_types" ];
      };

      mcp = pysuper.mcp.overridePythonAttrs (old: {
        version = "2.3.0";
        src = pypi "mcp" "2.3.0" "sha256-ixR6UEQc8FnciMaE4K7tNofwqg85xs3nuQMw7/0rNNg=";
        postPatch = "";
        dependencies = with pyself; [
          anyio
          httpx2
          jsonschema
          mcp-types
          opentelemetry-api
          pydantic
          pyjwt
          python-multipart
          sse-starlette
          starlette
          typing-extensions
          typing-inspection
          uvicorn
        ] ++ pyself.pyjwt.optional-dependencies.crypto;
        doCheck = false;
      });

      # Its main branch, for the headless API (open_document, create_document) that KiCad's development branch
      # serves: its bindings are generated from `kicad`'s own API definitions, the revision it pins
      # (packages/kicad-master.nix), in place of its git submodule. Bump both together.
      kicad-python = pysuper.kicad-python.overridePythonAttrs (old: {
        version = "0.9.0.dev0-76b47d2";
        src = fetchFromGitLab {
          owner = "kicad/code";
          repo = "kicad-python";
          rev = "76b47d25a826a56a301660f5f572dda968c84d59";
          hash = "sha256-KdhkRjQ4JPy4tLBl+MhHmiRRbhVFs5BjfUKAc5EO46k=";
        };
        postUnpack = ''
          mkdir -p $sourceRoot/kicad/api
          cp -r ${kicad.base.src}/api/proto $sourceRoot/kicad/api/proto
          chmod -R u+w $sourceRoot/kicad
        '';
        # protoc comes from nixpkgs' protobuf (nativeBuildInputs), not a wheel.
        postPatch = old.postPatch + ''
          substituteInPlace pyproject.toml --replace-fail '"protoc-wheel-0==29"' ""
        '';
        pythonRelaxDeps = [ "protobuf" "pynng" "jsonschema" "zstandard" ];
        dependencies = old.dependencies ++ [ pyself.jsonschema pyself.zstandard ];
        doCheck = false;
      });

      kicad-sch-api = pyself.buildPythonPackage {
        pname = "kicad-sch-api";
        version = "0.5.6";
        pyproject = true;
        src = pypi "kicad_sch_api" "0.5.6" "sha256-8AH6/98XRdelLpBja+K8SuNGOQlJH/+fnUD+H3hC024=";
        # Its own MCP server (mcp_server/, FastMCP on the 1.x SDK) isn't used, only the library.
        postPatch = ''
          rm -r mcp_server
        '';
        pythonRemoveDeps = [ "mcp" "fastmcp" ];
        build-system = [ pyself.setuptools pyself.wheel ];
        dependencies = with pyself; [ sexpdata pydantic jinja2 ];
        pythonImportsCheck = [ "kicad_sch_api" ];
      };
    };
  };
in
python.pkgs.buildPythonApplication (finalAttrs: {
  pname = "kicad-mcp-pro";
  version = "4.9.0";
  pyproject = true;

  src = pypi "kicad_mcp_pro" finalAttrs.version "sha256-mbsrDcd5obz7ryBxLjL0kHZOedjxe27PlR82dkZDtwk=";

  build-system = [ python.pkgs.hatchling ];

  # Minor versions ahead of nixpkgs, their APIs are what it uses.
  pythonRelaxDeps = [
    # It pins below 0.9, the git build its headless patch needs is 0.9.0.dev0.
    "kicad-python"
    "opentelemetry-exporter-otlp"
    "opentelemetry-sdk"
    "pydantic-settings"
    "pyjwt"
    "urllib3"
  ];

  dependencies = with python.pkgs; [
    anyio
    authlib
    cryptography
    idna
    kicad-python
    kicad-sch-api
    mcp
    opentelemetry-exporter-otlp
    opentelemetry-sdk
    packaging
    pydantic
    pydantic-settings
    pyjwt
    python-dotenv
    rich
    sexpdata
    starlette
    structlog
    typer
    urllib3
    websockets
    # sch_render_png and the visual diffs: SVG to PNG (upstream lists them as dev-only, they're runtime).
    cairosvg
    pillow
  ] ++ mcp.optional-dependencies.cli or [ ];

  # Headless KiCad (kicad-cli api-server, servers/kicad.nix): its development version counts as the release it leads
  # to, and the board selected with kicad_set_project is opened (or created) there, the one before saved and closed.
  patches = [ ./kicad-mcp-pro-headless.patch ];

  pythonImportsCheck = [ "kicad_mcp" ];

  meta = {
    description = "MCP server for KiCad schematic and PCB work";
    homepage = "https://github.com/oaslananka/kicad-mcp-pro";
    license = lib.licenses.mit;
    mainProgram = "kicad-mcp-pro";
  };
})
