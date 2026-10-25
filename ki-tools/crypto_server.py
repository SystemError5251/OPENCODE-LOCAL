#!/usr/bin/env python3
"""MCP server "ocl_crypto": encrypt / decrypt files with GnuPG (AES-256, symmetric).

The passphrase is generated once and stored outside the project with mode 0600. It is passed to gpg
through a file and never appears in tool input or output, so the model never sees it.
A private gpg home is used, so the user's own keyring is not touched.
"""

import os
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ocl_mcp import Server, ToolError, inside, new_output, rel, state_dir  # noqa: E402

server = Server("ocl_crypto", instructions="Encrypts files to <name>.gpg. Originals are kept; the user deletes them.")


def key_file():
    return Path(os.environ.get("OCL_CRYPTO_KEY") or state_dir("keys") / "crypto.pass")


def gpg(*args):
    exe = shutil.which("gpg")
    if not exe:
        raise ToolError("gpg is not installed (Debian: apt install gnupg, Termux: pkg install gnupg)")
    key = key_file()
    if not key.is_file():
        raise ToolError("no key yet - encrypt a file first, or restore your key backup")
    home = state_dir("gnupg")
    os.chmod(home, 0o700)
    cmd = [exe, "--homedir", str(home), "--batch", "--quiet", "--no-tty",
           "--pinentry-mode", "loopback", "--passphrase-file", str(key), *args]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    if r.returncode != 0:
        raise ToolError("gpg failed: " + (r.stderr.strip().splitlines() or ["unknown error"])[-1])


def ensure_key():
    key = key_file()
    if not key.exists():
        key.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd = os.open(key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(secrets.token_urlsafe(32) + "\n")
        return True
    return False


@server.tool("Show whether gpg is available and whether a key exists. Never shows the key itself.")
def status():
    key = key_file()
    return {
        "gpg": shutil.which("gpg") or "not installed",
        "key_exists": key.is_file(),
        "key_location": str(key),
        "reminder": "Back up the key file somewhere safe. Without it encrypted files cannot be recovered.",
    }


@server.tool(
    "Encrypt a file to <path>.gpg (AES-256). The original is kept.",
    {"path": {"type": "string"}, "output": {"type": "string", "description": "default: <path>.gpg"}},
    ["path"],
)
def encrypt(path, output=""):
    src = inside(path)
    if not src.is_file():
        raise ToolError("only single files can be encrypted (make a backup/tar first for folders)")
    out = new_output(output or rel(src) + ".gpg")
    created = ensure_key()
    gpg("--symmetric", "--cipher-algo", "AES256", "--output", str(out), str(src))
    msg = f"encrypted {rel(src)} -> {rel(out)}. The original is unchanged."
    if created:
        msg += f" A new key was created at {key_file()} - tell the user to back it up."
    return msg


@server.tool(
    "Decrypt a .gpg file made by encrypt.",
    {"path": {"type": "string"}, "output": {"type": "string", "description": "default: path without .gpg"}},
    ["path"],
)
def decrypt(path, output=""):
    src = inside(path)
    default = rel(src)[:-4] if rel(src).endswith(".gpg") else rel(src) + ".dec"
    out = new_output(output or default)
    gpg("--output", str(out), "--decrypt", str(src))
    return f"decrypted {rel(src)} -> {rel(out)}"


if __name__ == "__main__":
    server.run()
