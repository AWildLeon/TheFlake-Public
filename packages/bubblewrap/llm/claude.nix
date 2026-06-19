{ llm, mkLlmTool }:

mkLlmTool {
  package = llm.claude-code;
  configPaths = [
    ".claude"
    ".claude.json"
    ".cache/claude"
    ".cache/claude-cli-nodejs"
    ".local/share/claude"
  ];
}
