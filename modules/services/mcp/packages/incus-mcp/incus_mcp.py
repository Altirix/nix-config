"""Read-only MCP server for an Incus cluster, over its REST API with a client certificate.

Env:
  INCUS_ADDRESSES    "host[:port] ..." ([v6]:port), tried in order until one answers
  INCUS_SERVER_CERT  the cluster certificate, the only one trusted
  INCUS_CLIENT_CERT  client certificate
  INCUS_CLIENT_KEY   its key, default $CREDENTIALS_DIRECTORY/incus-client.key
  INCUS_PROJECT      default "default"
  INCUS_MAX_CHARS    cap on every tool result, default 60000
"""

import http.client
import json
import os
import ssl
from urllib.parse import quote, urlencode, urlsplit

from mcp.server.fastmcp import FastMCP

ADDRESSES = os.environ["INCUS_ADDRESSES"].split()
PROJECT = os.environ.get("INCUS_PROJECT", "default")
MAX_CHARS = int(os.environ.get("INCUS_MAX_CHARS", "60000"))
TIMEOUT = 15
# Bytes read from one response, logs are cut to their tail after.
READ_LIMIT = 8 * 1024 * 1024


def _context():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    # The pinned cluster certificate is the only trust anchor. Its names
    # don't cover every address a member is reached at.
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_REQUIRED
    ctx.load_verify_locations(os.environ["INCUS_SERVER_CERT"])
    key = os.environ.get("INCUS_CLIENT_KEY") or os.path.join(
        os.environ.get("CREDENTIALS_DIRECTORY", ""), "incus-client.key")
    ctx.load_cert_chain(os.environ["INCUS_CLIENT_CERT"], key)
    return ctx


CONTEXT = _context()
_order = list(ADDRESSES)


class IncusError(Exception):
    pass


def _request(path, params=None, raw=False):
    """GET only. Tries each address, the last one that answered first."""
    query = dict(params or {})
    query.setdefault("project", PROJECT)
    url = path + "?" + urlencode(query)
    errors = []
    for address in list(_order):
        parts = urlsplit("//" + address)
        conn = http.client.HTTPSConnection(parts.hostname, parts.port or 8443,
                                           context=CONTEXT, timeout=TIMEOUT)
        try:
            conn.request("GET", url)
            resp = conn.getresponse()
            body = resp.read(READ_LIMIT)
        except (OSError, http.client.HTTPException) as e:
            errors.append(f"{address}: {e}")
            continue
        finally:
            conn.close()
        _order.remove(address)
        _order.insert(0, address)
        if raw and resp.status == 200:
            return body.decode("utf-8", "replace")
        try:
            data = json.loads(body)
        except ValueError:
            raise IncusError(f"HTTP {resp.status}: {body[:200]!r}")
        if data.get("type") == "error" or resp.status != 200:
            raise IncusError(f"HTTP {resp.status}: {data.get('error')}")
        return data.get("metadata")
    raise IncusError("no Incus member reachable: " + "; ".join(errors))


def _bounded(value):
    text = value if isinstance(value, str) else json.dumps(value, indent=1, sort_keys=True)
    if len(text) > MAX_CHARS:
        text = text[:MAX_CHARS] + f"\n... truncated, {len(text) - MAX_CHARS} more chars"
    return text


def _tail(text, max_chars):
    max_chars = max(1, min(int(max_chars), MAX_CHARS))
    if len(text) > max_chars:
        return f"... {len(text) - max_chars} earlier chars left out\n" + text[-max_chars:]
    return text


def _name(value):
    if not value or "/" in value or value in (".", ".."):
        raise IncusError(f"invalid name {value!r}")
    return quote(value, safe="")


mcp = FastMCP("incus")


@mcp.tool()
def list_instances() -> str:
    """Instances in the project: status, type, cluster member, addresses, CPU and memory use."""
    out = []
    for i in _request("/1.0/instances", {"recursion": "2"}) or []:
        state = i.get("state") or {}
        addresses = [
            f"{nic}:{a['address']}"
            for nic, net in (state.get("network") or {}).items() if nic != "lo"
            for a in net.get("addresses", []) if a.get("scope") == "global"
        ]
        out.append({
            "name": i["name"],
            "type": i.get("type"),
            "status": i.get("status"),
            "location": i.get("location"),
            "profiles": i.get("profiles"),
            "addresses": addresses,
            "processes": state.get("processes"),
            "memory_usage": (state.get("memory") or {}).get("usage"),
            "cpu_seconds": (state.get("cpu") or {}).get("usage", 0) // 10**9,
            "created_at": i.get("created_at"),
        })
    return _bounded(out)


@mcp.tool()
def instance_info(name: str) -> str:
    """One instance: expanded config and devices, snapshots and state (network, disks, memory)."""
    info = _request(f"/1.0/instances/{_name(name)}", {"recursion": "1"})
    info["state"] = _request(f"/1.0/instances/{_name(name)}/state")
    return _bounded(info)


@mcp.tool()
def instance_console_log(name: str, max_chars: int = 16000) -> str:
    """The tail of an instance's console log (boot and serial output)."""
    return _tail(_request(f"/1.0/instances/{_name(name)}/console", raw=True), max_chars)


@mcp.tool()
def instance_logs(name: str, file: str = "", max_chars: int = 16000) -> str:
    """Without `file`, lists an instance's log files (qemu.log, lxc.log ...). With it, that file's tail."""
    if not file:
        return _bounded([p.rsplit("/", 1)[-1] for p in _request(f"/1.0/instances/{_name(name)}/logs") or []])
    return _tail(_request(f"/1.0/instances/{_name(name)}/logs/{_name(file)}", raw=True), max_chars)


@mcp.tool()
def list_networks() -> str:
    """Networks with their config and what uses them."""
    return _bounded(_request("/1.0/networks", {"recursion": "1"}))


@mcp.tool()
def network_state(name: str, member: str = "") -> str:
    """Link state, addresses and counters of a network on a cluster member (default: the one answering)."""
    return _bounded(_request(f"/1.0/networks/{_name(name)}/state", {"target": member} if member else None))


@mcp.tool()
def list_storage_pools() -> str:
    """Storage pools with driver, config and status."""
    return _bounded(_request("/1.0/storage-pools", {"recursion": "1"}))


@mcp.tool()
def storage_pool_resources(name: str, member: str = "") -> str:
    """Used and total space and inodes of a storage pool on a cluster member."""
    return _bounded(_request(f"/1.0/storage-pools/{_name(name)}/resources", {"target": member} if member else None))


@mcp.tool()
def list_storage_volumes(pool: str) -> str:
    """Volumes in a storage pool: name, type, content type, location, size."""
    out = [{
        "name": v.get("name"),
        "type": v.get("type"),
        "content_type": v.get("content_type"),
        "location": v.get("location"),
        "size": (v.get("config") or {}).get("size"),
        "used_by": v.get("used_by"),
    } for v in _request(f"/1.0/storage-pools/{_name(pool)}/volumes", {"recursion": "1"}) or []]
    return _bounded(out)


@mcp.tool()
def cluster_members() -> str:
    """Cluster members: status, roles, address, architecture, failure domain."""
    return _bounded(_request("/1.0/cluster/members", {"recursion": "1"}))


@mcp.tool()
def cluster_member_state(name: str) -> str:
    """A member's load, memory, uptime and storage pool usage."""
    return _bounded(_request(f"/1.0/cluster/members/{_name(name)}/state"))


@mcp.tool()
def server_resources(member: str = "") -> str:
    """Hardware of a cluster member: CPUs, memory, GPUs, NICs, disks."""
    return _bounded(_request("/1.0/resources", {"target": member} if member else None))


def main():
    mcp.run()


if __name__ == "__main__":
    main()
