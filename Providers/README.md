# Background modeling providers

In Settings, choose an agent and a model. The choice is saved per agent. In an empty workspace choose **Create from Description**. With a model open, use **Ask Agent** to revise the entire model or continue creating it. To target faces, pick them with a surface tool and choose **Edit Selected Faces**. Review the proposal in the sheet. Choose **Apply to Model** for an edit within your selection or **Confirm Outside Changes** to accept its highlighted effects on other faces.

## Connect from the installed app

1. Launch **ModelStudio** from Finder and open **Settings → Background modeling**.
2. Select an agent and a model. **Get a … API key** opens the provider’s key management page. Use an account with API access to the selected model.
3. Paste the key into **API key** and choose **Connect / Retry**. The app downloads and verifies the native runtime in your user Library, then asks that model to echo a random phrase. This small request uses the provider account and contains no model geometry.
4. Wait for **Connected** and the model name. A successful check saves the key in your Mac’s Keychain. Close Settings and start a modeling request. Repeat for each agent you want to use.

Settings remembers each agent’s model. After reopening Settings or switching models, **Key saved** means the app found the local credential. Choose **Connect / Retry** with the key field empty to check current access. For an authentication failure, check the account’s key and model entitlement or enter a replacement key. A failed replacement preserves the previously saved key. For a download failure, check the network and free space, then retry. **Reinstall and Retry** downloads a fresh verified runtime. **Disconnect** removes the saved key for that provider.

| Agent | Provisioned runtime | Key | Models in Settings |
| --- | --- | --- | --- |
| Codex | OpenAI Codex CLI 0.172.0 for macOS | OpenAI API key | `gpt-6.2-sol`, `gpt-6.2-astra` |
| Claude | Anthropic Claude Code 2.1.332 native executable | Anthropic API key | `sonnet`, `opus` |
| Antigravity | Google Antigravity SDK 0.1.24 with private CPython 3.12.16 | Gemini API key | `gemini-4-hydrogen`, `gemini-3.8-flash` |

Codex uses ephemeral noninteractive execution, disables shell, computer use, multi-agent, plugins, hooks and web search, and ignores user configuration and rules. [OpenAI noninteractive execution](https://developers.openai.com/codex/noninteractive)

Claude uses bare print mode, an empty built-in tool set, strict empty MCP configuration, disabled slash commands and disabled session persistence. [Claude CLI reference](https://code.claude.com/docs/en/cli-reference) · [Claude model aliases](https://code.claude.com/docs/en/model-config)

Antigravity uses Google’s local agent harness with the selected model, a finish-only tool policy and subagents disabled. Google publishes macOS wheels for both architectures. [SDK distribution](https://pypi.org/project/google-antigravity/0.1.24/) · [Google authentication](https://antigravity.google/docs/install) · [SDK model guidance](https://antigravity.google/docs/changelog)

## Packaging

The Xcode target copies the Runtime directory into the app’s resources. Its installer stages downloads under `~/Library/Application Support/3D Model Studio/Providers`. The packaged manifest pins both architectures’ native archive URLs and checksums. The Antigravity installer verifies its standalone Python archive and installs the architecture’s exact hash-locked wheels. Runtime setup uses system utilities supplied by macOS and the app’s resources. Each provider receives its own Keychain credential in its child environment. [Archive manifest](Runtime/artifacts.tsv) · [CPython distribution](https://github.com/astral-sh/python-build-standalone/releases/tag/20261124)

## Geometry crossing the boundary

All three adapters receive the same native projection as UTF-8 JSON following the modeling instructions on stdin. Each turn runs a new native process in a private temporary workspace and home directory. A macOS sandbox profile limits file reads to the runtime, required system paths and this turn, and limits regular file writes to the turn directory. The app removes that directory when the request finishes. The provider service receives the supplied text during inference. Expiry prevents subsequent studio disclosure and session reuse. Provider-side retention follows the service's terms.

- **Creation** includes the description, current draft surface and units. An empty draft starts in millimeters.
- **Revision** includes the instruction and complete active indexed surface. Vertices unreferenced by any face are excluded.
- **Selection** includes the instruction, target face IDs, those triangles, their referenced vertices and perimeter edges. File names, unrelated faces, isolated vertices, pins and whole-model measurements are excluded.
- An agent may request particular face IDs or neighbors across identified perimeter edges. The studio resolves them against the operation snapshot and highlights the additional triangles locally and presents their exact IDs and the reason. An approval token belongs to that one pending review.
- Approval resends the original instruction, original target and specifically approved context. The additional faces are labeled read-only. Declining displays the reason and ends the request. Closing, replacing, failing, or completing a request expires its approvals. Every new request takes a fresh Settings snapshot.
- A question keeps the original instruction, current-operation questions and answers, route and model together. After a creation or whole-model revision, the next revision in the same sheet includes the accepted turn history and current surface. Applying a selection edit returns to the workspace to pick the target of the next request. Prior dimensional targets expire. Closing the sheet clears the history.
- Each proposal includes an indexed patch, requested dimensional targets and a list of unsupported constraints. Negative vertex and face IDs are local to that patch. Existing IDs refer to the supplied surface. The studio rejects malformed references, conflicting edits, collapsed changed faces and unsupported constraints before review.
- Specify final whole-model spans with an axis, a value and a unit, for example “final span along X is 30 mm and final span along Z is 1/2 inch.” X measures width, Y depth and Z height. The studio also recognizes “7 mm tall”, “height to 7 mm”, “20 × 10 × 7 mm” (X, Y, Z), and a length in response to a direct final-span question such as “What height should the block have?”. Supported units are µm, mm, cm, m, in and ft.
- For an ambiguous dimension, the studio quotes the wording and asks for one final span at a time. Restate it with its axis and unit. Your original request and earlier answers stay in the same operation. Constraints such as hole diameter and wall thickness are outside the supported measurements. The provider's dimensional assessment cannot supply a missing target. The studio measures the candidate against each local target and current pin within ±0.01 mm, including the endpoints. The next operation starts with fresh targets.
- If you answer a height question with just “5”, the studio keeps height pending. Restate it as “final span along Z is 5 mm”, using your intended unit. You can specify a width while answering, and the studio will still ask for the missing height.
- The studio compares each selected-face proposal with the full original mesh on the Mac. Original and proposed views show affected selected faces in indigo and changes outside the selection in orange. These include shared-vertex movement, changes in which faces meet at a vertex or edge, removed faces and newly allocated face IDs. **Decline Edit** discards the candidate. **Confirm Outside Changes** accepts only the displayed proposal, subject to the current dimension and pin checks.

## Verification evidence

| Provider | Evidence from offline checks |
| --- | --- |
| Codex | Captured both GPT-6.2 choices and the ephemeral Codex CLI invocation. Scripted creation, revision and selection requests passed, including approval, refusal and expiry. |
| Claude | Captured both model aliases, print mode, the empty built-in tool set and strict MCP configuration. The same three workflows and disclosure checks passed. Switching from an in-flight Codex request to Claude discarded the late Codex reply. |
| Antigravity | Captured both Gemini choices at the Swift boundary. The packaged Python adapter passed the exact input and chosen model to an SDK double with the deny-by-default, finish-only policy. The same workflow and disclosure checks passed. |

Run `Tests/run-provider-checks.sh` from the checkout. Installer fixtures exercise all six archive selections, reject mismatched checksums and verify staging. Local process and credential doubles exercise the production setup controller, failed downloads and credentials, Keychain write failure, successful retry, repair, disconnect and reconnection. Each of the six provider/model choices receives a selected-face request through the native subprocess route. The process checks also cover 300 KB payloads, exclusion of inherited credentials, fresh turn directories and denial of reads of a separate model file.

Release acceptance remains open. On one clean Mac without Docker Desktop, install the release app, launch it from Finder, connect each agent in Settings and apply one conversational modeling operation with each. Record the app and macOS versions, provider/model choices, connection statuses and operation results. Keep API keys out of the record.

The same harness also runs the conversational geometry checks. For each route it creates a block after a clarification, revises that block and revises fresh STL, OBJ and 3MF imports. It checks physical spans, face identity, SceneKit updates and preservation of the current model after a rejection or provider failure.

The selected-face checks cover the same twelve combinations of provider route and model origin. They exercise in-selection application, disclosure followed by a separate edit review, stale confirmations, decline, requested and pinned height conflicts, and the SceneKit highlight groups. Topology cases include splitting a point without moving it, reversing the winding along a shared edge, removing a neighbor and adding a disconnected triangle.
