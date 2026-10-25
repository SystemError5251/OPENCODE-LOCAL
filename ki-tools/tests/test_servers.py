"""End-to-end tests: start each MCP server as a subprocess and talk JSON-RPC over stdio.

Run: python3 -m unittest discover -s ki-tools/tests
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent.parent


class Client:
    def __init__(self, script, project, home):
        env = dict(os.environ, OCL_HOME=str(home), OCL_PROJECT_ROOT=str(project))
        self.p = subprocess.Popen([sys.executable, "-I", str(TOOLS / script)], cwd=project, env=env,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.n = 0
        init = self.rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                                       "clientInfo": {"name": "test", "version": "0"}})
        assert init["capabilities"]["tools"] is not None
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")

    def rpc(self, method, params=None):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params or {}}) + "\n")
        self.p.stdin.flush()
        msg = json.loads(self.p.stdout.readline())
        assert msg["id"] == self.n
        if "error" in msg:
            raise RuntimeError(msg["error"])
        return msg["result"]

    def call(self, tool, **args):
        r = self.rpc("tools/call", {"name": tool, "arguments": args})
        return r["isError"], r["content"][0]["text"]

    def ok(self, tool, **args):
        err, text = self.call(tool, **args)
        assert not err, text
        return text

    def close(self):
        self.p.stdin.close()
        self.p.wait(5)
        self.p.stdout.close()


class Base(unittest.TestCase):
    script = None

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.project = self.tmp / "proj"
        self.home = self.tmp / "home"
        self.project.mkdir()
        (self.project / "a.txt").write_text("hello\n")
        (self.project / "sub").mkdir()
        (self.project / "sub" / "b.txt").write_text("world\n")
        (self.tmp / "secret.txt").write_text("outside\n")
        self.c = Client(self.script, self.project, self.home)

    def tearDown(self):
        self.c.close()
        shutil.rmtree(self.tmp)


class TestProtocol(Base):
    script = "files_server.py"

    def test_list_and_unknown(self):
        names = {t["name"] for t in self.c.rpc("tools/list")["tools"]}
        self.assertEqual(names, {"info", "largest", "trash", "list_trash", "restore", "move"})
        self.assertTrue(self.c.call("nope")[0])
        with self.assertRaises(RuntimeError):
            self.c.rpc("does/not/exist")
        self.assertEqual(self.c.rpc("ping"), {})


class TestFiles(Base):
    script = "files_server.py"

    def test_sandbox(self):
        for bad in ("../secret.txt", str(self.tmp / "secret.txt"), "sub/../../secret.txt"):
            err, text = self.c.call("info", path=bad)
            self.assertTrue(err)
            self.assertIn("outside the project", text)
        os.symlink(self.tmp / "secret.txt", self.project / "link")
        self.assertTrue(self.c.call("info", path="link")[0])

    def test_trash_restore(self):
        self.c.ok("trash", path="sub/b.txt")
        self.assertFalse((self.project / "sub/b.txt").exists())
        items = json.loads(self.c.ok("list_trash"))
        self.c.ok("restore", id=items[0]["id"])
        self.assertEqual((self.project / "sub/b.txt").read_text(), "world\n")
        self.assertTrue(self.c.call("trash", path=".")[0])

    def test_move_never_overwrites(self):
        self.assertTrue(self.c.call("move", source="a.txt", target="sub/b.txt")[0])
        self.c.ok("move", source="a.txt", target="new/a.txt")
        self.assertTrue((self.project / "new/a.txt").exists())


class TestBackup(Base):
    script = "backup_server.py"

    def test_cycle(self):
        self.c.ok("create", note="first")
        backups = json.loads(self.c.ok("list"))
        bid = backups[0]["id"]
        self.assertEqual(backups[0]["files"], 2)
        self.assertFalse(any(self.project.rglob("*.tar.gz")), "backup must be stored outside the project")
        (self.project / "a.txt").write_text("changed\n")
        (self.project / "c.txt").write_text("new\n")
        (self.project / "sub/b.txt").unlink()
        d = json.loads(self.c.ok("diff", id=bid))
        self.assertEqual(d, {"added": ["c.txt"], "removed": ["sub/b.txt"], "changed": ["a.txt"]})
        self.c.ok("restore", id=bid, only="sub")
        self.assertEqual((self.project / f"restored-{bid}/sub/b.txt").read_text(), "world\n")
        self.assertFalse((self.project / f"restored-{bid}/a.txt").exists())
        self.assertTrue(self.c.call("restore", id=bid)[0], "second restore into same folder must fail")
        self.assertTrue(self.c.call("diff", id="../x")[0])


@unittest.skipUnless(shutil.which("gpg"), "gpg not installed")
class TestCrypto(Base):
    script = "crypto_server.py"

    def test_roundtrip(self):
        self.assertTrue(self.c.call("decrypt", path="a.txt")[0], "no key yet")
        text = self.c.ok("encrypt", path="a.txt")
        self.assertIn("back it up", text)
        key = self.home / "keys/crypto.pass"
        self.assertEqual(key.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(key.read_text().strip(), text)
        self.assertNotIn(key.read_text().strip(), self.c.ok("status"))
        self.assertTrue((self.project / "a.txt").exists(), "original is kept")
        self.assertNotIn(b"hello", (self.project / "a.txt.gpg").read_bytes())
        self.assertTrue(self.c.call("decrypt", path="a.txt.gpg")[0], "must not overwrite a.txt")
        self.c.ok("decrypt", path="a.txt.gpg", output="copy.txt")
        self.assertEqual((self.project / "copy.txt").read_text(), "hello\n")


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg not installed")
class TestVideo(Base):
    script = "video_server.py"

    def setUp(self):
        super().setUp()
        subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=duration=3:size=320x240:rate=10",
                        "-f", "lavfi", "-i", "sine=duration=3", "-shortest", "-c:v", "libx264", "-c:a", "aac",
                        str(self.project / "in.mp4")], check=True)

    def test_info_convert_trim(self):
        info = json.loads(self.c.ok("info", path="in.mp4"))
        self.assertAlmostEqual(info["duration_s"], 3, delta=0.2)
        self.c.ok("convert", input="in.mp4", output="out.m4a", preset="m4a")
        self.assertTrue(self.c.call("convert", input="in.mp4", output="out.m4a", preset="m4a")[0], "no overwrite")
        self.assertTrue(self.c.call("convert", input="in.mp4", output="x.mp3", preset="m4a")[0], "extension check")
        self.c.ok("trim", input="in.mp4", output="cut.mp4", start="1", end="2")
        self.assertTrue(self.c.call("trim", input="in.mp4", output="c2.mp4", start="1; rm", end="2")[0])
        self.assertTrue(self.c.call("info", path="../secret.txt")[0])


if __name__ == "__main__":
    unittest.main()
