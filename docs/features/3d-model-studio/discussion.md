# Discussion — 3D Model Studio

### Answer to Q-001 · 2026-11-25

Для кого и для каких задач предназначена первая версия?

A + B + C

### Answer to Q-002 · 2026-11-25

Какой набор сценариев обязателен уже в первой версии?

A. Оба сценария в небольшом объёме: открыть готовую модель или создать новую через AI, затем доработать вручную и командами.

### Answer to Q-003 · 2026-11-25

Какой результат для проектирования физических деталей обязателен уже в первой версии?

C. В первой версии обязательны точные размеры и проверка геометрии на пригодность к 3D-печати.

### Answer to Q-004 · 2026-11-25

Какой выбор AI-агентов обязателен уже в первой версии?

B. В первой версии обязательны Codex, Claude и Antigravity с переключением в настройках.

### AI updated the requirements · 2026-11-25

DEC-001, DEC-002, DEC-003 written into the overview.

### AI updated the requirements · 2026-11-25

DEC-004 written into REQ-002, the overview.

### AI updated the requirements · 2026-11-25

DEC-005 written into REQ-003, REQ-004, REQ-005.

### AI updated the requirements · 2026-11-25

DEC-006 written into the overview.

### AI updated the requirements · 2026-11-25

DEC-007 written into REQ-003, REQ-005, REQ-006.

### AI updated the requirements · 2026-11-25

DEC-009 written into REQ-005.

### Codex · 2026-11-25

The Cockpit branch prerequisite is complete. After fetching, local `main` and `origin/main` both pointed to `263a252d6adc7435afceeebe68268413fcad9dce`. The `feat/3d-model-studio` branch was created at that commit with the approved requirements, accepted decisions, specification findings, and implementation plan carried forward. Implementation tasks and requirement acceptance checks remain pending. The README update specified by DEC-008 is still pending.

### Codex · 2026-11-25

DEC-008 is reflected in the README (commit `e2f02e2`), with implementation evidence recorded on F-001. I-1 is in progress on `feat/3d-model-studio`. The planned SwiftUI shell opens an untitled workspace with a viewport and standard macOS Settings. I-5 still owns provider feasibility and agent/model selection.

### Codex · 2026-11-25

I-1 implementation is complete on the feature branch. The `ModelStudio.xcodeproj` application target and shared `ModelStudio` scheme identify `ModelStudio.app` (`com.github.t-boris.3d-model-studio`, macOS 14+). The SwiftUI entry point opens the active untitled workspace and its empty viewport and supplies the native Settings scene. The workspace toolbar links to Settings. Xcode resolved the target and scheme metadata, and the SwiftUI sources passed static type-checking for macOS 14. REQ-001's Swift UI criterion is checked. Its macOS runtime criterion and the launch verification in I-1 remain pending because the Cockpit step disables building. I-2 owns loading and viewing geometry, and I-5 retains provider feasibility, integration, and agent/model selection.

### Codex · 2026-11-25

I-2 is in progress. All three file readers will produce the same indexed mesh. The open workflow will apply declared units and transforms, request missing units, and replace the active workspace only on success. I-4 and I-6 retain the manual and conversational acceptance checks.

### Codex · 2026-11-25

I-2 implementation and fixture handoff are complete. The workspace Open command and toolbar use the same transactional import path. All three blocks passed source-level checks of unit handling, transformed coordinates, indexed connectivity, face identity, SceneKit geometry and a model-layer height edit. Invalid input and a canceled unit choice retained the active edited mesh. I-4 and I-6 can reuse the 7 mm height edit in Fixtures/Import/README.md. Interactive camera gestures and end-user editing remain pending. Building was disabled. The pre-existing overview.md lifecycle change is excluded from the I-2 commits at the supervisor’s direction.

### Codex · 2026-11-25

I-3 in progress. REQ-008 records the editable save and reopen obligation of DEC-006. V1 dimensional targets are whole-model X width, Y depth and Z height of the indexed surface in model coordinates. All requested and pinned targets use the same inclusive absolute tolerance of 0.01 mm, after unit conversion. Slicer export remains a separate obligation.

### Codex · 2026-11-25

I-3 implementation complete in faf6658, following specification commit db8881f. The workspace supports explicit pins, a shared geometry commit path and versioned editable save/open. Tests/run-dimension-checks.sh passed for a new block and all three import fixtures, including failed proposals and damaged saves. The app sources type-check for macOS 14. Building was disabled, so interactive file panels and UI gestures await a build-enabled pass. Subsequent manual tools, provider workflows, selection confirmation and slicer export remain in their respective steps.

### Agent · 2026-11-25

I-4 started on the I-3 workspace. The manual tool scope is recorded in REQ-004. Verification will exercise the same production edit and commit path on the new block and each of the three I-2 fixtures.

### Agent · 2026-11-25

I-4 implementation and interpreted checks completed in 0b4fdc3 and 9bc7ce9. The same workspace path moved a point, reshaped shared top vertices and extruded the selected patch on a new block, STL, OBJ and transformed 3MF. Tests checked SceneKit face picking and refreshed geometry, stable cap IDs, perimeter walls and pin conflicts. Application sources passed macOS 14 static type-checking. Building was disabled, so interactive app verification remains pending. The existing overview lifecycle edit is supervisor-reserved.

### Agent · 2026-11-25

Cockpit I-5 (agent integrations, currently numbered I-6 in the working plan) underway. REQ-006 and DEC-003/007 require actual provider agents, explicit model selection and operation-limited input. Supervisor requires offline verification, no credential use or provisioning, and individual evidence. Runtime/provider entitlement remains unverified. Earlier overview and plan edits remain reserved. Findings F-001/F-006 retain their resolved specification status.

### Agent · 2026-11-25

Cockpit I-5 / current plan's Agent integrations and model settings task: implemented and verified offline in 24c6341, 20a6575 and 45a1d7f. Settings routes to actual Codex CLI, Claude Code or the Google Antigravity SDK. Each route passed creation/draft, revision and selected-face payload checks. The local access review highlights and lists the specific requested triangles, explains the reason, and expires on completion, refusal, cancellation, errors or replacement. Provider-specific evidence and setup are in Providers/README.md. The interpreter exercised the production session and native process I/O using offline doubles; all dimension and manual editing regressions also passed. REQ-006 criteria for end-to-end conversational modeling remain open. Build, deployment, live credentials and agent execution were excluded. Earlier reserved plan and overview edits remain untouched.

### Agent · 2026-11-25

Managed I-6 (conversational creation and whole-model revision) is in progress. Clarifications will retain the operation’s description, answers, geometry and route. The studio will resolve indexed patches locally, review operation-specific dimensional targets, and publish through I-3. Selection proposal application remains a separate task. Verification will use scripted replies at the existing adapter boundary and all three I-2 imports.

### Agent · 2026-11-25

Managed I-6 implementation complete in 04a8e98. The interpreted provider harness passed all twelve route/origin combinations, including repeated revisions of each import, and verified local preview, SceneKit updates, current pins, requested lengths and rejection. Dimension and manual-edit suites passed. Application sources type-checked for macOS 14 with warnings as errors. No app build, interactive launch, authenticated provider run or deployment occurred. The reserved lifecycle and externally renumbered plan files remain under supervisor control. Selected-face application remains assigned separately.

### Agent · 2026-11-25

Managed I-7, selected-face edits, is in progress. Existing viewport picking and provider disclosure are in place. Remaining work covers the local comparison against the original full mesh, affected-region preview, proposal-specific edit confirmation and commit-time validation of requested and pinned dimensions. The edited implementation plan and overview remain reserved.

### Agent · 2026-11-25

Managed I-7, Review edits beyond selected faces, is complete at the implementation and offline verification level in 502fe64. Scripted replies through all three provider routes exercised scoped edits and outside-selection confirmation on a new block and all three imported blocks. The interpreted checks covered before/after SceneKit highlights, independent disclosure and edit decisions, decline, stale confirmation IDs, topology-only effects and atomic dimension rejection. The manual and dimension regression suites also passed. Build-disabled controls leave app launch and interactive review unverified. Live providers were not invoked. The implementation uses the existing indexed mesh, Swift collections and SceneKit. The two pre-existing plan and lifecycle edits remain reserved.

### Agent · 2026-11-25

Approved I-8 in progress. Implement REQ-007 on the local indexed triangle mesh and expose its result in the workspace. REQ-009 now records the export obligation. The pre-approval DEC-006 explicitly leaves the format open, so the exporter and slicer acceptance remain blocked. The previously reserved plan and overview changes remain outside this step.
