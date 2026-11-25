"""One studio turn in a fresh Google Antigravity harness."""
import asyncio
import sys

from google.antigravity import Agent, CapabilitiesConfig, LocalAgentConfig
from google.antigravity.hooks import policy
from google.antigravity.types import BuiltinTools


async def main():
    config = LocalAgentConfig(
        model=sys.argv[1],
        workspaces=["/studio"],
        capabilities=CapabilitiesConfig(enable_subagents=False, enabled_tools=[BuiltinTools.FINISH]),
        policies=[policy.deny_all(), policy.allow(BuiltinTools.FINISH)],
    )
    async with Agent(config) as agent:
        response = await agent.chat(sys.stdin.read())
        print(await response.text())


if __name__ == "__main__":
    asyncio.run(main())
