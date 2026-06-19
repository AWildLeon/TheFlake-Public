import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { spawn } from "node:child_process";
import path from "node:path";

const AGENTS = ["claude", "gemini", "codex"] as const;

const CodingAgentParams = Type.Object({
  agent: Type.Union(
    AGENTS.map((agent) => Type.Literal(agent)),
    {
      description: "Coding agent CLI to run.",
    },
  ),
  prompt: Type.String({
    description: "Task/prompt to pass to the delegated coding agent.",
  }),
  cwd: Type.Optional(
    Type.String({
      description:
        "Working directory, relative to Pi's current cwd. Defaults to Pi's current cwd.",
    }),
  ),
  args: Type.Optional(
    Type.Array(Type.String(), {
      description:
        "Override the default CLI arguments. Use {prompt} as a placeholder for the prompt. Defaults: claude -p {prompt}; gemini -p {prompt}; codex exec {prompt}.",
    }),
  ),
  timeoutSeconds: Type.Optional(
    Type.Number({
      description: "Timeout in seconds. Default 300, maximum 1800.",
    }),
  ),
});

type Agent = (typeof AGENTS)[number];

type CodingAgentParams = {
  agent: Agent;
  prompt: string;
  cwd?: string;
  args?: string[];
  timeoutSeconds?: number;
};

const DEFAULT_ARGS: Record<Agent, string[]> = {
  claude: ["-p", "{prompt}"],
  gemini: ["-p", "{prompt}"],
  codex: ["exec", "{prompt}"],
};

const COMMAND_ENV: Record<Agent, string> = {
  claude: "PI_CODING_AGENT_CLAUDE_COMMAND",
  gemini: "PI_CODING_AGENT_GEMINI_COMMAND",
  codex: "PI_CODING_AGENT_CODEX_COMMAND",
};

function commandFor(agent: Agent): string {
  return process.env[COMMAND_ENV[agent]] || agent;
}

function renderArgs(agent: Agent, prompt: string, args?: string[]): string[] {
  const selected = args && args.length > 0 ? args : DEFAULT_ARGS[agent];
  return selected.map((arg) =>
    arg === "{prompt}" ? prompt : arg.replaceAll("{prompt}", prompt),
  );
}

function resolveCwd(baseCwd: string, requested?: string): string {
  const resolved = requested ? path.resolve(baseCwd, requested) : baseCwd;
  const relative = path.relative(baseCwd, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(
      `Refusing to run delegated agent outside project cwd: ${requested}`,
    );
  }
  return resolved;
}

function truncate(text: string, max = 40_000): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max)}\n\n[truncated ${text.length - max} characters]`;
}

function runCommand(
  command: string,
  args: string[],
  cwd: string,
  timeoutSeconds: number,
  signal?: AbortSignal,
): Promise<{
  exitCode: number | null;
  stdout: string;
  stderr: string;
  timedOut: boolean;
}> {
  return new Promise((resolve, reject) => {
    let stdout = "";
    let stderr = "";
    let timedOut = false;

    const child = spawn(command, args, {
      cwd,
      env: {
        ...process.env,
        PI_DELEGATED_AGENT: "1",
      },
      stdio: ["ignore", "pipe", "pipe"],
    });

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 2_000).unref();
    }, timeoutSeconds * 1000);

    const abort = () => {
      child.kill("SIGTERM");
      setTimeout(() => child.kill("SIGKILL"), 2_000).unref();
    };

    signal?.addEventListener("abort", abort, { once: true });

    child.stdout?.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr?.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      signal?.removeEventListener("abort", abort);
      reject(error);
    });
    child.on("close", (exitCode) => {
      clearTimeout(timer);
      signal?.removeEventListener("abort", abort);
      resolve({
        exitCode,
        stdout: truncate(stdout),
        stderr: truncate(stderr),
        timedOut,
      });
    });
  });
}

export default function codingAgentsExtension(pi: ExtensionAPI) {
  pi.registerTool({
    name: "coding_agent_cli",
    label: "Coding Agent CLI",
    description:
      "Delegate a task to another coding-agent CLI such as Claude Code, Gemini CLI, or Codex CLI.",
    promptSnippet:
      "Run another coding-agent CLI (claude, gemini, codex) and return its stdout/stderr.",
    promptGuidelines: [
      "Use coding_agent_cli only when the user explicitly asks to consult or run another coding agent, or when a second opinion is clearly useful.",
      "When using coding_agent_cli, provide a precise prompt and summarize the delegated agent's output for the user.",
      "coding_agent_cli may run tools that modify files depending on the delegated agent and prompt; avoid requesting file changes unless the user asked for them.",
    ],
    parameters: CodingAgentParams,
    async execute(
      _toolCallId,
      params: CodingAgentParams,
      signal,
      onUpdate,
      ctx,
    ) {
      const timeoutSeconds = Math.min(
        Math.max(params.timeoutSeconds ?? 300, 1),
        1800,
      );
      const cwd = resolveCwd(ctx.cwd, params.cwd);
      const command = commandFor(params.agent);
      const args = renderArgs(params.agent, params.prompt, params.args);

      onUpdate?.({
        content: [
          {
            type: "text",
            text: `Running ${command} ${args.map((arg) => JSON.stringify(arg)).join(" ")} in ${cwd}`,
          },
        ],
      });

      try {
        const result = await runCommand(
          command,
          args,
          cwd,
          timeoutSeconds,
          signal,
        );
        const text = [
          `agent: ${params.agent}`,
          `command: ${command}`,
          `args: ${JSON.stringify(args)}`,
          `cwd: ${cwd}`,
          `exitCode: ${result.exitCode}`,
          `timedOut: ${result.timedOut}`,
          "",
          "stdout:",
          result.stdout || "(empty)",
          "",
          "stderr:",
          result.stderr || "(empty)",
        ].join("\n");

        return {
          content: [{ type: "text", text }],
          details: { ...result, agent: params.agent, command, args, cwd },
          isError: result.exitCode !== 0 || result.timedOut,
        };
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        return {
          content: [
            { type: "text", text: `Failed to run ${params.agent}: ${message}` },
          ],
          details: { agent: params.agent, command, args, cwd, error: message },
          isError: true,
        };
      }
    },
  });

  pi.registerCommand("agents", {
    description:
      "Show delegated coding-agent CLI defaults and environment overrides.",
    handler: async (_args, ctx) => {
      const lines = AGENTS.map(
        (agent) =>
          `${agent}: command=${commandFor(agent)} args=${JSON.stringify(DEFAULT_ARGS[agent])} override=${COMMAND_ENV[agent]}`,
      );
      ctx.ui.notify(lines.join("\n"), "info");
    },
  });
}
