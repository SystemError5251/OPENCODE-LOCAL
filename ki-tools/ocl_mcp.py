"""Minimal MCP stdio server (JSON-RPC 2.0, one message per line). Standard library only.

No third-party packages on purpose: nothing to download, nothing to audit besides this file.
Each server registers tools with @server.tool(...) and calls server.run().
"""

import json
import os
import sys
import traceback
from pathlib import Path

PROTOCOL_VERSION = "2025-06-18"


class ToolError(Exception):
    """An expected failure that is reported to the model as a tool error, not a crash."""


class Server:
    def __init__(self, name, version="0.1.0", instructions=None):
        self.name = name
        self.version = version
        self.instructions = instructions
        self.tools = {}

    def tool(self, description, properties=None, required=None, name=None):
        """Register a function as a tool (named after the function unless NAME is given).
        Arguments arrive as keyword arguments."""

        def wrap(fn):
            tool_name = name or fn.__name__
            self.tools[tool_name] = {
                "fn": fn,
                "def": {
                    "name": tool_name,
                    "description": description,
                    "inputSchema": {
                        "type": "object",
                        "properties": properties or {},
                        "required": required or [],
                        "additionalProperties": False,
                    },
                },
            }
            return fn

        return wrap

    # --- JSON-RPC -------------------------------------------------------------

    def _handle(self, msg):
        method = msg.get("method")
        params = msg.get("params") or {}
        if method == "initialize":
            result = {
                "protocolVersion": params.get("protocolVersion", PROTOCOL_VERSION),
                "capabilities": {"tools": {"listChanged": False}},
                "serverInfo": {"name": self.name, "version": self.version},
            }
            if self.instructions:
                result["instructions"] = self.instructions
            return result
        if method == "ping":
            return {}
        if method == "tools/list":
            return {"tools": [t["def"] for t in self.tools.values()]}
        if method == "tools/call":
            return self._call(params.get("name"), params.get("arguments") or {})
        raise LookupError(method)

    def _call(self, name, args):
        tool = self.tools.get(name)
        if tool is None:
            return _text(f"unknown tool: {name}", error=True)
        try:
            out = tool["fn"](**args)
        except ToolError as e:
            return _text(str(e), error=True)
        except TypeError as e:
            return _text(f"bad arguments: {e}", error=True)
        except Exception as e:  # report, never crash the server
            traceback.print_exc(file=sys.stderr)
            return _text(f"{type(e).__name__}: {e}", error=True)
        if not isinstance(out, str):
            out = json.dumps(out, indent=2, ensure_ascii=False)
        return _text(out)

    def run(self):
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                _send({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}})
                continue
            if "id" not in msg:  # notification, e.g. notifications/initialized
                continue
            try:
                _send({"jsonrpc": "2.0", "id": msg["id"], "result": self._handle(msg)})
            except LookupError as e:
                _send({"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": f"method not found: {e}"}})


def _text(text, error=False):
    return {"content": [{"type": "text", "text": text}], "isError": error}


def _send(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


# --- Sandbox ------------------------------------------------------------------

def project_root():
    """The directory OpenCode was started in. All tool paths must stay inside it."""
    return Path(os.environ.get("OCL_PROJECT_ROOT") or os.getcwd()).resolve()


def inside(path, must_exist=True):
    """Resolve PATH relative to the project root and refuse anything outside it (incl. via symlinks)."""
    if not isinstance(path, str) or not path or "\x00" in path:
        raise ToolError("invalid path")
    root = project_root()
    p = (root / path).resolve()
    if p != root and root not in p.parents:
        raise ToolError(f"path is outside the project: {path}")
    if must_exist and not p.exists():
        raise ToolError(f"not found: {path}")
    return p


def new_output(path):
    """Like inside(), for a file to be created. Never overwrites."""
    p = inside(path, must_exist=False)
    if p.exists():
        raise ToolError(f"refusing to overwrite existing file: {rel(p)}")
    if not p.parent.is_dir():
        raise ToolError(f"directory does not exist: {rel(p.parent)}")
    return p


def rel(p):
    try:
        return str(Path(p).relative_to(project_root())) or "."
    except ValueError:
        return str(p)


def state_dir(*parts):
    """Per-user data directory outside every project (backups, keys)."""
    base = Path(os.environ.get("OCL_HOME") or Path.home() / ".local/share/opencode-local")
    d = base.joinpath(*parts)
    d.mkdir(parents=True, exist_ok=True, mode=0o700)
    return d


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
