"""Execute the packaged adapter against an in-memory SDK double."""
import asyncio
import io
import os
import runpy
import sys
from contextlib import redirect_stdout
from types import ModuleType
from unittest.mock import AsyncMock, MagicMock, patch


def check(model):
    sdk = ModuleType("google.antigravity")
    sdk.Agent = MagicMock()
    sdk.LocalAgentConfig = MagicMock()
    sdk.CapabilitiesConfig = MagicMock()
    hooks = ModuleType("google.antigravity.hooks")
    hooks.policy = MagicMock()
    types = ModuleType("google.antigravity.types")
    types.BuiltinTools = MagicMock()
    modules = {
        "google": ModuleType("google"),
        "google.antigravity": sdk,
        "google.antigravity.hooks": hooks,
        "google.antigravity.types": types,
    }
    response = MagicMock()
    response.text = AsyncMock(return_value='{"kind":"explanation","message":"Done"}')
    agent = sdk.Agent.return_value.__aenter__.return_value
    agent.chat = AsyncMock(return_value=response)
    payload = '{"operation":"Edit Selected Faces","targetFaceIDs":[1]}'
    output = io.StringIO()
    with patch.dict(sys.modules, modules), patch.object(sys, "stdin", io.StringIO(payload)), \
         patch.object(sys, "argv", ["agent.py", model]), redirect_stdout(output):
        asyncio.run(runpy.run_path("Providers/Runtime/antigravity.py")["main"]())
    sdk.CapabilitiesConfig.assert_called_once_with(enable_subagents=False, enabled_tools=[types.BuiltinTools.FINISH])
    hooks.policy.deny_all.assert_called_once_with()
    hooks.policy.allow.assert_called_once_with(types.BuiltinTools.FINISH)
    sdk.LocalAgentConfig.assert_called_once_with(
        model=model, workspaces=[os.getcwd()], capabilities=sdk.CapabilitiesConfig.return_value,
        policies=[hooks.policy.deny_all.return_value, hooks.policy.allow.return_value],
    )
    sdk.Agent.assert_called_once_with(sdk.LocalAgentConfig.return_value)
    agent.chat.assert_awaited_once_with(payload)
    assert output.getvalue().strip() == '{"kind":"explanation","message":"Done"}'


for choice in ["gemini-4-hydrogen", "gemini-3.8-flash"]:
    check(choice)
print("Antigravity SDK double received the exact input, selected model and finish-only policy.")
