# 3D Model Studio

3D Model Studio is a native macOS application with a SwiftUI interface. Use Open (Command-O) to load an STL, OBJ, or Core 3MF mesh. Choose the source unit for STL and OBJ. The viewport displays the active mesh and its unit. Drag to rotate and scroll to zoom.

## Run locally

On macOS 14 or later, open `ModelStudio.xcodeproj` in Xcode and run the shared `ModelStudio` scheme. It builds `ModelStudio.app` with bundle identifier `com.github.t-boris.3d-model-studio`. Open Settings from the workspace toolbar or app menu, or press Command-Comma.

The [import fixtures](Fixtures/Import/README.md) include one block per format, expected geometry, and dimensions for the manual and conversational editing tasks.

## v1 scope

- Open STL, OBJ, and 3MF models as editable geometry and inspect them in a 3D viewport.
- Create models from descriptions and refine new or imported models through manual edits or conversation, including instructions targeting selected faces.
- Use precise dimensional controls with explicit units and optional persistent dimensions, and check geometry for 3D printing.
- Save editable models for later work and export geometry for slicing while preserving physical dimensions.
- Use Codex, Claude, or Antigravity for conversational modeling. All three integrations are required in v1, with agent switching and model selection in Settings.

Supported integration methods and modeling capabilities for Codex, Claude, and Antigravity still require technical verification. [Implementation task I-5](docs/features/3d-model-studio/implementation/plan.md#i-5-integrate-all-three-agents-with-model-settings-and-geometry-access-controls) tracks that work.

## Specification

The confirmed brief, decisions and requirements are in [`docs/features/3d-model-studio/`](docs/features/3d-model-studio/overview.md). Open this folder in MarkView to continue them.

### Requirements

- REQ-001 Native macOS application
- REQ-002 3D model viewing
- REQ-003 Conversational model creation
- REQ-004 Manual geometry editing
- REQ-005 Selection-based AI editing
- REQ-006 Agent and model configuration
- REQ-007 3D-printing geometry validation
