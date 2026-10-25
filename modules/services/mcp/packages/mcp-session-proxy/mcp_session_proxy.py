"""Streamable HTTP in front of a stdio MCP server, one server process per MCP session.

mcp-proxy shares one process between every client, so a stateful server (REA has one open target)
is shared too. Here each session (an initialize without Mcp-Session-Id) starts its own process,
which lives until the client DELETEs the session, its process exits, or it has been idle with no
request open for --idle-timeout seconds. At --max-sessions, the session idle longest makes room for a
new one (clients that vanish without a DELETE would hold their slot otherwise), and only when every
session has a request open is the new one refused. Only /mcp, no SSE.

mcp-session-proxy [--host H] [--port P] [--max-sessions N] [--idle-timeout S] [--pass-environment] -- command [args...]
"""

import argparse
import logging
import os
import time
from http import HTTPStatus
from uuid import uuid4

import anyio
import uvicorn
from mcp.client.session import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client
from mcp.server.streamable_http import MCP_SESSION_ID_HEADER, StreamableHTTPServerTransport
from mcp_proxy.proxy_server import create_proxy_server
from starlette.requests import Request
from starlette.responses import JSONResponse

logger = logging.getLogger("mcp-session-proxy")


def error(status, message):
    return JSONResponse({"jsonrpc": "2.0", "id": "server-error", "error": {"code": -32600, "message": message}},
                        status_code=status)


class Session:
    def __init__(self):
        self.id = uuid4().hex
        self.transport = StreamableHTTPServerTransport(mcp_session_id=self.id)
        self.scope = anyio.CancelScope()
        self.open = 0
        self.last = time.monotonic()


class Sessions:
    def __init__(self, server, max_sessions, idle_timeout):
        self.server = server
        self.max_sessions = max_sessions
        self.idle_timeout = idle_timeout
        self.sessions = {}
        # Sessions whose server is still starting count towards the cap too.
        self.starting = 0
        self.tg = None

    async def run(self, session, *, task_status):
        # The server process, its proxy and the transport live and die together.
        started = False
        with session.scope:
            try:
                async with stdio_client(self.server) as streams, ClientSession(*streams) as backend:
                    app = await create_proxy_server(backend)
                    async with session.transport.connect() as (read, write):
                        self.sessions[session.id] = session
                        logger.info("session %s started (%d open)", session.id, len(self.sessions))
                        started = True
                        task_status.started(None)
                        await app.run(read, write, app.create_initialization_options())
            except Exception as e:
                logger.exception("session %s failed", session.id)
                # The caller is still waiting on a session that never came up, hand it the error.
                if not started:
                    task_status.started(e)
            finally:
                self.sessions.pop(session.id, None)
                logger.info("session %s ended (%d open)", session.id, len(self.sessions))

    async def reap(self):
        while True:
            await anyio.sleep(30)
            now = time.monotonic()
            for session in list(self.sessions.values()):
                if session.open == 0 and now - session.last > self.idle_timeout:
                    logger.info("session %s idle, closing", session.id)
                    session.scope.cancel()

    async def handle(self, scope, receive, send):
        session_id = Request(scope, receive).headers.get(MCP_SESSION_ID_HEADER)
        if session_id is None:
            if len(self.sessions) + self.starting >= self.max_sessions:
                idle = [s for s in self.sessions.values() if s.open == 0]
                if not idle:
                    return await error(HTTPStatus.SERVICE_UNAVAILABLE, "Too many sessions")(scope, receive, send)
                oldest = min(idle, key=lambda s: s.last)
                logger.info("session %s idle longest, closing for a new one", oldest.id)
                oldest.scope.cancel()
                self.sessions.pop(oldest.id, None)
            session = Session()
            self.starting += 1
            try:
                failed = await self.tg.start(self.run, session)
            finally:
                self.starting -= 1
            if failed is not None:
                return await error(HTTPStatus.BAD_GATEWAY, f"Server failed to start: {failed}")(scope, receive, send)
        elif session_id in self.sessions:
            session = self.sessions[session_id]
        else:
            return await error(HTTPStatus.NOT_FOUND, "Session not found")(scope, receive, send)

        session.open += 1
        try:
            await session.transport.handle_request(scope, receive, send)
        finally:
            session.open -= 1
            session.last = time.monotonic()
        if session.transport.is_terminated:
            session.scope.cancel()


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument("--max-sessions", type=int, default=4)
    parser.add_argument("--idle-timeout", type=int, default=1800)
    parser.add_argument("--pass-environment", action="store_true")
    parser.add_argument("command")
    parser.add_argument("args", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    # As mcp-proxy: without --pass-environment the server gets the SDK's minimal environment.
    server = StdioServerParameters(command=args.command, args=args.args,
                                   env=dict(os.environ) if args.pass_environment else None)
    sessions = Sessions(server, args.max_sessions, args.idle_timeout)

    async def app(scope, receive, send):
        if scope["type"] == "lifespan":
            message = await receive()
            if message["type"] == "lifespan.startup":
                await send({"type": "lifespan.startup.complete"})
            await receive()
            await send({"type": "lifespan.shutdown.complete"})
        elif scope["type"] == "http" and scope["path"] == "/mcp":
            await sessions.handle(scope, receive, send)
        else:
            await error(HTTPStatus.NOT_FOUND, "Not found")(scope, receive, send)

    async def serve():
        async with anyio.create_task_group() as tg:
            sessions.tg = tg
            tg.start_soon(sessions.reap)
            await uvicorn.Server(uvicorn.Config(app, host=args.host, port=args.port, log_level="warning")).serve()
            tg.cancel_scope.cancel()

    anyio.run(serve)


if __name__ == "__main__":
    main()
