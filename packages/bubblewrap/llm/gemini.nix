{ llm, mkLlmTool }:

mkLlmTool {
  package = llm.gemini-cli;
  configPaths = [ ".gemini" ];
}
