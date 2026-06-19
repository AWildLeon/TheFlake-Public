{ llm, mkLlmTool }:

mkLlmTool {
  package = llm.pi;
  configPaths = [
    ".pi"
    ".gemini"
    ".config/gemini"
    ".cache/gemini"
    ".local/share/gemini"
    ".codex"
    ".config/codex"
    ".cache/codex"
    ".local/share/codex"
    ".claude"
    ".claude.json"
    ".config/claude"
    ".cache/claude"
    ".cache/claude-cli-nodejs"
    ".local/share/claude"
  ];
}
