{ llm, mkLlmTool }:

mkLlmTool {
  package = llm.codex;
  configPaths = [
    ".codex"
    ".config/codex"
    ".cache/codex"
    ".local/share/codex"
  ];
}
