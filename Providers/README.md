# Background modeling providers

In Settings, choose an agent and a model. The choice is saved per agent. In an empty workspace choose **Create from Description**. With a model open, use **Ask Agent** to revise the entire model or continue creating it. To target faces, pick them with a surface tool and choose **Edit Selected Faces**. The sheet returns the provider's explanation or mesh proposal. Applying conversational proposals and confirming edits outside the target are separate implementation tasks.

## Runtime setup

Install and start Docker Desktop on the Mac. Prepare each desired runtime image once from the repository root. The build context is the Providers directory. Only the Dockerfile and the Antigravity adapter are included.

```sh
docker build --target codex -t modelstudio-codex:1 Providers
docker build --target claude -t modelstudio-claude:1 Providers
docker build --target antigravity -t modelstudio-antigravity:1 Providers
```

Launch ModelStudio with the selected provider's environment variable available to the app process. The studio supplies only that variable to the agent. Model access depends on the account. Each request runs the prepared image on the local Docker socket. A missing runtime, unavailable model, failed request or malformed response ends the operation and preserves the model.

| Agent | Noninteractive interface | Models in Settings | Runtime variable |
| --- | --- | --- | --- |
| Codex | OpenAI Codex CLI 0.172.0, `codex exec --model … -`, final message on stdout | `gpt-6.2-sol`, `gpt-6.2-astra` | `CODEX_API_KEY` |
| Claude | Anthropic Claude Code 2.1.332, `claude --print --model …`, piped prompt and text reply | `sonnet`, `opus` (official model aliases) | `ANTHROPIC_API_KEY` |
| Antigravity | Google's Python SDK 0.1.24, one `Agent.chat` call with `LocalAgentConfig.model` | `gemini-4-hydrogen`, `gemini-3.8-flash` | `GEMINI_API_KEY` |

Codex uses ephemeral execution with user configuration and rules ignored. Shell, computer use, plugins, hooks and web search are disabled. The installed CLI help confirms the flags. [Noninteractive execution](https://developers.openai.com/codex/noninteractive) · [Codex model guidance](https://developers.openai.com/api/docs/guides/model-selection)

Claude uses bare print mode, an empty built-in tool set, strict empty MCP configuration, disabled slash commands and disabled session persistence. The installed CLI help confirms the flags. [CLI reference](https://code.claude.com/docs/en/cli-reference) · [Model aliases](https://code.claude.com/docs/en/model-config)

Antigravity runs Google's agent harness with its finish tool as the sole enabled and permitted tool. The SDK policy denies other tool calls and disables subagents. Google publishes Linux wheels for both Intel and Apple Silicon Docker hosts. [SDK and model configuration](https://github.com/google-antigravity/antigravity-sdk-python) · [Tool capabilities](https://antigravity.google/docs/sdk/tools/) · [SDK distribution](https://pypi.org/project/google-antigravity/0.1.24/)

## Geometry crossing the boundary

All three adapters receive the same native projection as UTF-8 JSON following the modeling instructions on stdin. Each turn gets a fresh non-root container with an empty working directory, a read-only image, temporary writable storage, and no host volumes or previous session. The provider service receives the supplied text during inference. Expiry prevents subsequent studio disclosure and session reuse. Provider-side retention follows the service's terms.

- **Creation** includes the description, current draft surface and units. An empty draft starts in millimeters.
- **Revision** includes the instruction and complete active indexed surface. Vertices unreferenced by any face are excluded.
- **Selection** includes the instruction, target face IDs, those triangles, their referenced vertices and perimeter edges. File names, unrelated faces, isolated vertices, pins and whole-model measurements are excluded.
- An agent may request particular face IDs or neighbors across identified perimeter edges. The studio resolves them against the operation snapshot and presents the exact additional face IDs and reason. An approval token belongs to that one pending review.
- Approval resends the original instruction, original target and specifically approved context. The additional faces are labeled read-only. Declining displays the reason and ends the request. Closing, replacing, failing, or completing a request expires its approvals. Every new request takes a fresh Settings snapshot.
- The reply is a typed explanation, access request or indexed mesh patch. A patch can describe added, changed or removed geometry. The provider has no workspace commit capability.

Offline verification uses the production session, request encoder, provider routes and response decoder with a scripted transport. Run `Tests/run-provider-checks.sh` from the checkout. Authenticated model access, runtime image execution and live modeling quality require separate verification.
