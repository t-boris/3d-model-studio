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
