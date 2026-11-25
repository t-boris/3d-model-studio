# Background modeling providers

In Settings, choose an agent and a model. The choice is saved per agent. In an empty workspace choose **Create from Description**. With a model open, use **Ask Agent** to revise the entire model or continue creating it. To target faces, pick them with a surface tool and choose **Edit Selected Faces**. Review the proposal in the sheet. Choose **Apply to Model** for an edit within your selection or **Confirm Outside Changes** to accept its highlighted effects on other faces.

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
- An agent may request particular face IDs or neighbors across identified perimeter edges. The studio resolves them against the operation snapshot and highlights the additional triangles locally and presents their exact IDs and the reason. An approval token belongs to that one pending review.
- Approval resends the original instruction, original target and specifically approved context. The additional faces are labeled read-only. Declining displays the reason and ends the request. Closing, replacing, failing, or completing a request expires its approvals. Every new request takes a fresh Settings snapshot.
- A question keeps the original instruction, current-operation questions and answers, route and model together. After a creation or whole-model revision, the next revision in the same sheet includes the accepted turn history and current surface. Applying a selection edit returns to the workspace to pick the target of the next request. Prior dimensional targets expire. Closing the sheet clears the history.
- Each proposal includes an indexed patch, requested dimensional targets and a list of unsupported constraints. Negative vertex and face IDs are local to that patch. Existing IDs refer to the supplied surface. The studio rejects malformed references, conflicting edits, collapsed changed faces and unsupported constraints before review.
- The studio independently recognizes common explicit whole-model spans such as “7 mm tall”, “height to 7 mm”, “20 × 10 × 7 mm” and a length in answer to a question naming one axis. The provider interprets other phrasing as final axis spans or reports an unsupported constraint. Review shows the requested values alongside the locally measured spans. Apply uses the current workspace geometry and pins for the final check.
- The studio compares each selected-face proposal with the full original mesh on the Mac. Original and proposed views show affected selected faces in indigo and changes outside the selection in orange. These include shared-vertex movement, changes in which faces meet at a vertex or edge, removed faces and newly allocated face IDs. **Decline Edit** discards the candidate. **Confirm Outside Changes** accepts only the displayed proposal, subject to the current dimension and pin checks.

## Verification evidence

| Provider | Evidence from offline checks |
| --- | --- |
| Codex | Captured both GPT-6.2 choices and the ephemeral Codex CLI invocation. Scripted creation, revision and selection requests passed, including approval, refusal and expiry. |
| Claude | Captured both model aliases, print mode, the empty built-in tool set and strict MCP configuration. The same three workflows and disclosure checks passed. Switching from an in-flight Codex request to Claude discarded the late Codex reply. |
| Antigravity | Captured both Gemini choices at the Swift boundary. The packaged Python adapter passed the exact input and chosen model to an SDK double with the deny-by-default, finish-only policy. The same workflow and disclosure checks passed. |

The checks use the production session, request encoder, provider routes and response decoder with a scripted transport. A local echo process also verified the native subprocess I/O with a 300 KB payload for each route. Run `Tests/run-provider-checks.sh` from the checkout. Authenticated model access, runtime image execution and live modeling quality require separate verification.

The same harness also runs the conversational geometry checks. For each route it creates a block after a clarification, revises that block and revises fresh STL, OBJ and 3MF imports. It checks physical spans, face identity, SceneKit updates and preservation of the current model after a rejection or provider failure.

The selected-face checks cover the same twelve combinations of provider route and model origin. They exercise in-selection application, disclosure followed by a separate edit review, stale confirmations, decline, requested and pinned height conflicts, and the SceneKit highlight groups. Topology cases include splitting a point without moving it, reversing the winding along a shared edge, removing a neighbor and adding a disconnected triangle.
