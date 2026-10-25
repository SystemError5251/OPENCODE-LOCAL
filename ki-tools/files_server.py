#!/usr/bin/env python3
"""MCP server "ocl_files": safe file helpers inside the project. Nothing is ever deleted:
"trash" moves files into .trash/ inside the project, where they can be restored."""

import hashlib
import json
import os
import re
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ocl_mcp import Server, ToolError, human, inside, project_root, rel  # noqa: E402

TRASH = ".trash"
server = Server("ocl_files", instructions="Use trash instead of deleting files. All paths are relative to the project.")

# Small models copy what the read tool shows ("12: code", "(End of file - total 3 lines)") into
# their edits. write and replace remove that decoration instead of failing.
LINE_NO = re.compile(r"^ *\d+: ?")
READ_FOOTER = re.compile(r"^\((End of file|File has more lines).*\)$")
SECRET = re.compile(r"(^|/)(\.env(\..*)?|id_rsa.*|id_ed25519.*|.*\.pem|.*\.key|.*\.kdbx)$")


def undecorate(text):
    lines = [line for line in text.split("\n") if not READ_FOOTER.match(line.strip())]
    # Strip only when it clearly is read output: the first line is numbered, most lines are, and
    # the numbers count up by one (lines the model added without a number are kept as they are).
    filled = [line for line in lines if line.strip()]
    numbers = [int(m.group().strip(" :")) for m in map(LINE_NO.match, filled) if m]
    if (filled and LINE_NO.match(filled[0]) and 2 * len(numbers) >= len(filled)
            and numbers == list(range(numbers[0], numbers[0] + len(numbers)))):
        lines = [LINE_NO.sub("", line, count=1) for line in lines]
    return "\n".join(lines)


def unescape_line(line):
    """Turn a literal backslash-n or backslash-t outside of quotes into a real line break or tab.
    Outside a string literal they are never valid code; small models write them by mistake."""
    out, quote, i = [], None, 0
    while i < len(line):
        c = line[i]
        if c == "\\" and i + 1 < len(line):
            nxt = line[i + 1]
            if quote is None and nxt in "nt":
                out.append("\n" if nxt == "n" else "\t")
            else:
                out.append(c + nxt)
            i += 2
            continue
        if c in "\"'`":
            quote = None if quote == c else (c if quote is None else quote)
        out.append(c)
        i += 1
    return "".join(out)


def clean(text):
    return undecorate("\n".join(unescape_line(line) for line in text.split("\n")))


def editable(path):
    p = inside(path, must_exist=False)
    r = rel(p)
    if SECRET.search(r) and not r.endswith(".env.example"):
        raise ToolError(f"refusing to change a secrets file: {r}")
    if p.relative_to(project_root()).parts[:1] in ((TRASH,), (".git",)) or p.is_dir():
        raise ToolError(f"not a file you can edit: {r}")
    return p


def keep_old(p):
    """Copy the current version into the trash so a write or replace can be undone with restore."""
    root = project_root()
    entry = time.strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}-{time.monotonic_ns() % 100000}"
    dest = root / TRASH / entry / p.relative_to(root)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p, dest)
    (root / TRASH / entry / ".origin.json").write_text(json.dumps({"path": rel(p)}))
    return entry


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


@server.tool(
    "Create a file or replace its whole content. Pass the complete new file. The old version goes to"
    " the trash, so it can be restored.",
    {"path": {"type": "string"}, "content": {"type": "string", "description": "the complete new file content"}},
    ["path", "content"],
)
def write(path, content):
    p = editable(path)
    content = clean(content)
    if content and not content.endswith("\n"):
        content += "\n"
    entry = keep_old(p) if p.exists() else None
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content)
    lines = content.count("\n")
    if entry:
        return f"wrote {rel(p)} ({lines} lines). Old version: restore(id='{entry}') after moving this one away."
    return f"created {rel(p)} ({lines} lines)"


@server.tool(
    "Replace one exact piece of text in a file. old must appear exactly once; copy it from the file.",
    {"path": {"type": "string"}, "old": {"type": "string"}, "new": {"type": "string"}},
    ["path", "old", "new"],
)
def replace(path, old, new):
    p = editable(path)
    if not p.is_file():
        raise ToolError(f"not found: {path} (use write to create it)")
    text = p.read_text()
    if text.count(old) != 1:
        old, new = clean(old), clean(new)
    n = text.count(old) if old else 0
    if n == 0:
        raise ToolError("old text not found. Read the file again and copy old exactly, or use write.")
    if n > 1:
        raise ToolError(f"old text appears {n} times. Include more surrounding lines so it is unique.")
    if old.endswith("\n") and new and not new.endswith("\n"):
        new += "\n"
    if old == new:
        raise ToolError("old and new are the same, nothing to change")
    keep_old(p)
    p.write_text(text.replace(old, new, 1))
    return f"changed {rel(p)}"


if __name__ == "__main__":
    server.run()
