# 3D Model Studio

3D Model Studio is a native macOS application with a SwiftUI interface. Use Open (Command-O) to load an STL, OBJ, or Core 3MF mesh. Choose the source unit for STL and OBJ. The viewport displays the active mesh and its unit. Drag to rotate and scroll to zoom.

## Run locally

On macOS 14 or later, open `ModelStudio.xcodeproj` in Xcode and run the shared `ModelStudio` scheme. It builds `ModelStudio.app` with bundle identifier `com.github.t-boris.3d-model-studio`. Open Settings from the workspace toolbar or app menu, or press Command-Comma.

The [import fixtures](Fixtures/Import/README.md) include one block per format, expected geometry, and dimensions for the manual and conversational editing tasks.

## Dimensions and editable files

In an empty workspace, choose **New Block** to start with a 10 mm cube, or open a mesh. Width (X), depth (Y), and height (Z) measure the distance from the minimum to the maximum coordinate along each model axis. Only vertices used by faces contribute to those bounds. Rotating the view leaves the measurements unchanged. V1 dimensional targets cover these three whole-model spans.

Enter a nonnegative length and select µm, mm, cm, m, in, or ft. **Set Once** scales that axis about its minimum coordinate. **Pin Current** preserves the measured span. **Change Pin** resizes the model and replaces that pin together. **Unpin** releases it for later edits. Resizing a flat axis cannot create thickness.

Each proposed span must fall within **±0.01 mm**, inclusive, of its target after conversion to millimeters. The same absolute tolerance applies to the current operation’s targets and every active pin. A conflict reports the dimension, target, and proposed measurement and leaves the geometry and pins intact.

Use **Save Editable Model…** (Command-S) to write a `.studio3d` file. Use **Open…** (Command-O) to resume editing. The file stores the indexed mesh and face identities, model unit, and explicit pins with their target values and units.

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
- REQ-008 Save and reopen an editable model
