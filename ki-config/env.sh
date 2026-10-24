# shellcheck shell=bash
# Sourced before starting OpenCode. Turns off every feature that would reach the internet.
export OPENCODE_DISABLE_AUTOUPDATE=1      # no update checks or notices
export OPENCODE_DISABLE_MODELS_FETCH=1    # do not download the models.dev catalogue
export OPENCODE_DISABLE_LSP_DOWNLOAD=1    # do not download language servers
export OPENCODE_DISABLE_DEFAULT_PLUGINS=1 # no built-in cloud auth plugins
export OPENCODE_DISABLE_CLAUDE_CODE=1     # ignore ~/.claude prompts and skills
export OPENCODE_AUTO_SHARE=false
# The TUI talks to its own local server; keep that and llama-server off any proxy.
export NO_PROXY="localhost,127.0.0.1${NO_PROXY:+,$NO_PROXY}"
export no_proxy="$NO_PROXY"
# llama-server API key. Only needed when the model host is not 127.0.0.1 (see docs/security.md).
export OCL_LLAMA_API_KEY="${OCL_LLAMA_API_KEY:-local-no-key}"
