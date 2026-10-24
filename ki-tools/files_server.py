#!/usr/bin/env python3
"""MCP server "ocl_files": safe file helpers inside the project. Nothing is ever deleted:
"trash" moves files into .trash/ inside the project, where they can be restored."""

import hashlib
import json
import os
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ocl_mcp import Server, ToolError, human, inside, project_root, rel  # noqa: E402

TRASH = ".trash"
server = Server("ocl_files", instructions="Use trash instead of deleting files. All paths are relative to the project.")


def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


@server.tool(
    "Size, modification time and SHA-256 of a file, or size and file count of a directory.",
    {"path": {"type": "string", "description": "file or directory, relative to the project"}},
    ["path"],
)
def info(path):
    p = inside(path)
    st = p.stat()
    out = {"path": rel(p), "modified": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(st.st_mtime))}
    if p.is_dir():
        files = [f for f in p.rglob("*") if f.is_file()]
        out.update(type="directory", files=len(files), size=human(sum(f.stat().st_size for f in files)))
    else:
        out.update(type="file", size=human(st.st_size), sha256=sha256(p))
    return out


@server.tool(
    "List the largest files below a directory.",
    {
        "path": {"type": "string", "description": "directory, default: project root"},
        "top": {"type": "integer", "description": "number of entries, default 10"},
    },
)
def largest(path=".", top=10):
    p = inside(path)
    files = [f for f in p.rglob("*") if f.is_file() and TRASH not in f.relative_to(project_root()).parts[:1]]
    files.sort(key=lambda f: f.stat().st_size, reverse=True)
    return [{"path": rel(f), "size": human(f.stat().st_size)} for f in files[: max(1, min(int(top), 100))]]


@server.tool(
    "Move a file or directory into the project's .trash/ folder instead of deleting it. Can be undone with restore.",
    {"path": {"type": "string"}},
    ["path"],
)
def trash(path):
    p = inside(path)
    root = project_root()
    if p == root or p.relative_to(root).parts[0] in (TRASH, ".git"):
        raise ToolError("refusing to trash the project root, .git or the trash itself")
    entry = time.strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}-{time.monotonic_ns() % 100000}"
    dest = root / TRASH / entry / p.relative_to(root)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(p), str(dest))
    (root / TRASH / entry / ".origin.json").write_text(json.dumps({"path": rel(p)}))
    return f"moved {rel(p)} to trash (id {entry}). Undo with restore(id='{entry}')."


@server.tool("List what is in the project's trash.")
def list_trash():
    t = project_root() / TRASH
    if not t.is_dir():
        return "trash is empty"
    items = []
    for d in sorted(t.iterdir()):
        meta = d / ".origin.json"
        if meta.is_file():
            items.append({"id": d.name, "path": json.loads(meta.read_text())["path"]})
    return items or "trash is empty"


@server.tool(
    "Put a trashed file back where it was. Fails if something exists at that place now.",
    {"id": {"type": "string", "description": "id from list_trash"}},
    ["id"],
)
def restore(id):
    if "/" in id or id.startswith("."):
        raise ToolError("invalid id")
    root = project_root()
    entry = root / TRASH / id
    meta = entry / ".origin.json"
    if not meta.is_file():
        raise ToolError(f"no trash entry {id}")
    original = inside(json.loads(meta.read_text())["path"], must_exist=False)
    if original.exists():
        raise ToolError(f"{rel(original)} exists, move it away first")
    original.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(entry / original.relative_to(root)), str(original))
    shutil.rmtree(entry)  # only the now-empty trash entry
    return f"restored {rel(original)}"


@server.tool(
    "Rename or move a file inside the project. Never overwrites.",
    {"source": {"type": "string"}, "target": {"type": "string"}},
    ["source", "target"],
)
def move(source, target):
    src = inside(source)
    dst = inside(target, must_exist=False)
    if dst.exists():
        raise ToolError(f"target exists: {rel(dst)}")
    if src == project_root():
        raise ToolError("cannot move the project root")
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(src), str(dst))
    return f"moved {rel(src)} -> {rel(dst)}"


if __name__ == "__main__":
    server.run()
