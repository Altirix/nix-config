# mcp-call <url> '<[[method, params], ...]>'
# One streamable HTTP session: initialize, then each request in turn. Prints
# {"serverInfo": ..., "results": [...]} and fails on any HTTP or JSON-RPC error.
# Answers the server's pings (on the GET stream), playwright closes the session on a missed one.
import json
import sys
import threading
import urllib.parse
import http.client


class Session:
    def __init__(self, url):
        self.url = urllib.parse.urlsplit(url)
        self.headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        self.next_id = 0

    def post(self, message):
        url = self.url
        for _ in range(5):
            conn = http.client.HTTPConnection(url.hostname, url.port, timeout=900)
            conn.request("POST", url.path, json.dumps(message), self.headers)
            res = conn.getresponse()
            # markitdown redirects /mcp to /mcp/.
            if res.status in (307, 308):
                url = self.url = urllib.parse.urlsplit(urllib.parse.urljoin(url.geturl(), res.getheader("Location")))
                res.read()
                continue
            if res.status not in (200, 202):
                sys.exit(f"{message.get('method')}: HTTP {res.status} {res.read()[:2000]!r}")
            if res.getheader("Mcp-Session-Id"):
                self.headers["Mcp-Session-Id"] = res.getheader("Mcp-Session-Id")
            return res
        sys.exit("too many redirects")

    def messages(self, res):
        # SSE data: lines, answering the server's pings on the way.
        for line in res:
            line = line.decode().rstrip("\r\n")
            if not line.startswith("data:"):
                continue
            message = json.loads(line[5:])
            if message.get("method") == "ping" and "id" in message:
                pong = {"jsonrpc": "2.0", "id": message["id"], "result": {}}
                threading.Thread(target=lambda m=pong: self.post(m).read(), daemon=True).start()
            else:
                yield message

    def listen(self):
        # The stream for messages outside a request, where the server sends its pings.
        conn = http.client.HTTPConnection(self.url.hostname, self.url.port, timeout=900)
        conn.request("GET", self.url.path, headers={**self.headers, "Accept": "text/event-stream"})
        res = conn.getresponse()
        if res.status == 200:
            for _ in self.messages(res):
                pass

    def request(self, method, params):
        self.next_id += 1
        res = self.post({"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params})
        if res.getheader("Content-Type", "").startswith("application/json"):
            return self.result(method, json.loads(res.read()))
        for message in self.messages(res):
            if message.get("id") == self.next_id:
                return self.result(method, message)
        sys.exit(f"{method}: stream ended without a response")

    def result(self, method, message):
        if "error" in message:
            sys.exit(f"{method}: {message['error']}")
        return message["result"]


session = Session(sys.argv[1])
init = session.request("initialize", {
    "protocolVersion": "2025-06-18",
    "capabilities": {},
    "clientInfo": {"name": "mcp-call", "version": "1"},
})
session.headers["MCP-Protocol-Version"] = init["protocolVersion"]
session.post({"jsonrpc": "2.0", "method": "notifications/initialized"}).read()
threading.Thread(target=session.listen, daemon=True).start()
results = [session.request(method, params) for method, params in json.loads(sys.argv[2])]
print(json.dumps({"serverInfo": init["serverInfo"], "results": results}))
