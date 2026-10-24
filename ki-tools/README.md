# Local MCP tools (Phase 4 – not started)

Planned local MCP servers, written in Python, started by OpenCode over stdio (no network port):

| Tool | Purpose |
|---|---|
| `crypto` | encrypt / decrypt files with a local key |
| `video` | local video conversion (ffmpeg) |
| `backup` | versioned backups of the project directory |
| `files` | safe file operations restricted to the project |

They will be registered in `ki-config/opencode.json` under `mcp` with `"type": "local"`, and their
tools will start with `"ask"` permissions like everything else.
