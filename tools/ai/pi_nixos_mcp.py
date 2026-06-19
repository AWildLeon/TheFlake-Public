#!/usr/bin/env python3
"""Tiny stdio MCP client wrapper for the local mcp-nixos server.

Usage:
  pi-nixos-mcp '{"action":"search","query":"nginx"}'
  pi-nixos-mcp nix '{"action":"info","query":"services.nginx.enable","type":"option"}'
  pi-nixos-mcp nix_versions '{"query":"firefox","version":"150"}'
  pi-nixos-mcp --tools
"""

import asyncio
import json
import os
import sys

from fastmcp import Client

CONFIG = {
    "mcpServers": {
        "nixos": {
            "command": os.environ.get("MCP_NIXOS_COMMAND", "mcp-nixos"),
            "args": [],
        }
    }
}


def usage(code: int = 2) -> None:
    print(__doc__.strip(), file=sys.stderr)
    raise SystemExit(code)


async def main() -> None:
    args = sys.argv[1:]
    if not args or args in (["-h"], ["--help"]):
        usage(0 if args else 2)

    async with Client(CONFIG) as client:
        if args == ["--tools"]:
            tools = await client.list_tools()
            for tool in tools:
                desc = (tool.description or "").splitlines()[0]
                print(f"{tool.name}\t{desc}")
            return

        if len(args) == 1:
            tool = "nix"
            raw_payload = args[0]
        elif len(args) == 2:
            tool, raw_payload = args
        else:
            usage()

        try:
            payload = json.loads(raw_payload)
        except json.JSONDecodeError as e:
            print(f"Invalid JSON payload: {e}", file=sys.stderr)
            raise SystemExit(2) from e

        result = await client.call_tool(tool, payload)
        data = getattr(result, "data", None)
        if data is not None:
            print(data if isinstance(data, str) else json.dumps(data, indent=2, sort_keys=True))
        else:
            for item in result.content:
                text = getattr(item, "text", None)
                if text is not None:
                    print(text)


if __name__ == "__main__":
    asyncio.run(main())
