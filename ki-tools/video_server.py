#!/usr/bin/env python3
"""MCP server "ocl_video": local video/audio work with ffmpeg.
Fixed presets only (no free-form ffmpeg arguments), local files only, never overwrites."""

import json
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ocl_mcp import Server, ToolError, human, inside, new_output, rel  # noqa: E402

server = Server("ocl_video", instructions="Conversions can take minutes on a phone. Outputs never overwrite files.")

PRESETS = {
    "mp4": (".mp4", ["-c:v", "libx264", "-preset", "medium", "-crf", "23", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart"]),
    "mp4-small": (".mp4", ["-c:v", "libx264", "-preset", "veryfast", "-crf", "30", "-vf", "scale=-2:'min(720,ih)'", "-c:a", "aac", "-b:a", "96k", "-movflags", "+faststart"]),
    "webm": (".webm", ["-c:v", "libvpx-vp9", "-crf", "34", "-b:v", "0", "-c:a", "libopus", "-b:a", "96k"]),
    "mp3": (".mp3", ["-vn", "-c:a", "libmp3lame", "-q:a", "2"]),
    "m4a": (".m4a", ["-vn", "-c:a", "aac", "-b:a", "160k"]),
    "gif": (".gif", ["-vf", "fps=10,scale=480:-1:flags=lanczos", "-an"]),
}
TIME = re.compile(r"^\d{1,2}(:\d{2}){0,2}(\.\d+)?$")


def tool(name):
    exe = shutil.which(name)
    if not exe:
        raise ToolError(f"{name} is not installed (Debian: apt install ffmpeg, Termux: pkg install ffmpeg)")
    return exe


def ffmpeg(inp, out, args, pre=()):
    # -protocol_whitelist file: inputs such as playlists cannot pull anything from the network.
    cmd = [tool("ffmpeg"), "-hide_banner", "-nostdin", "-n", "-loglevel", "error",
           "-protocol_whitelist", "file", *pre, "-i", str(inp), *args, str(out)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=6 * 3600)
    if r.returncode != 0:
        if out.exists():
            out.unlink()  # remove our own partial output
        raise ToolError("ffmpeg failed: " + (r.stderr.strip()[-500:] or "unknown error"))
    return f"{rel(inp)} -> {rel(out)} ({human(out.stat().st_size)})"


def check_output(output, ext):
    if not output.lower().endswith(ext):
        raise ToolError(f"output must end with {ext}")
    return new_output(output)


@server.tool(
    "Duration, resolution, codecs and size of a media file.",
    {"path": {"type": "string"}},
    ["path"],
)
def info(path):
    p = inside(path)
    r = subprocess.run([tool("ffprobe"), "-v", "error", "-protocol_whitelist", "file", "-print_format", "json",
                        "-show_format", "-show_streams", str(p)], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise ToolError("not a media file ffprobe can read")
    d = json.loads(r.stdout)
    fmt = d.get("format", {})
    streams = []
    for s in d.get("streams", []):
        item = {"type": s.get("codec_type"), "codec": s.get("codec_name")}
        if s.get("codec_type") == "video":
            item.update(width=s.get("width"), height=s.get("height"), fps=s.get("avg_frame_rate"))
        if s.get("codec_type") == "audio":
            item.update(channels=s.get("channels"), sample_rate=s.get("sample_rate"))
        streams.append(item)
    return {"path": rel(p), "duration_s": round(float(fmt.get("duration", 0)), 2),
            "size": human(int(fmt.get("size", 0))), "format": fmt.get("format_name"), "streams": streams}


@server.tool(
    "Convert a file with a fixed preset: " + ", ".join(PRESETS) + ".",
    {"input": {"type": "string"}, "output": {"type": "string"}, "preset": {"type": "string", "enum": list(PRESETS)}},
    ["input", "output", "preset"],
)
def convert(input, output, preset):
    if preset not in PRESETS:
        raise ToolError(f"unknown preset, use one of {', '.join(PRESETS)}")
    ext, args = PRESETS[preset]
    return ffmpeg(inside(input), check_output(output, ext), args)


@server.tool(
    "Cut a section without re-encoding (fast, cuts at the nearest keyframe). Times as SS, MM:SS or HH:MM:SS.",
    {"input": {"type": "string"}, "output": {"type": "string"}, "start": {"type": "string"}, "end": {"type": "string"}},
    ["input", "output", "start", "end"],
)
def trim(input, output, start, end):
    if not (TIME.match(start) and TIME.match(end)):
        raise ToolError("times must look like 90, 01:30 or 00:01:30.5")
    src = inside(input)
    ext = os.path.splitext(src.name)[1].lower()
    return ffmpeg(src, check_output(output, ext), ["-c", "copy"], pre=["-ss", start, "-to", end])


if __name__ == "__main__":
    server.run()
