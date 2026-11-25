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

## Conversational modeling

Choose **Create from Description…** in an empty workspace, or **Ask Agent → Revise Entire Model…** on an open model. Describe the shape or change. For example, ask for a block 2 cm wide and 1 cm deep. If the agent asks for the height, enter a value and unit and choose **Send Answer**.

Review the proposed surface, measured spans and requested dimensions. **Apply to Model** updates the workspace and lets you continue the conversation on the edited geometry. **Discard** keeps the previous model. A conflicting pin or unsupported measurement appears in the sheet. Closing the sheet ends its conversation.

## Print geometry checks

Choose **Print Checks** below the viewport, then **Run Checks**. A failed result lists problems by face or edge. Select a problem to see its face IDs and suggested correction. The inspection viewport highlights the faces in orange, marks a corner, and draws the affected edge in pink when applicable. After a geometry edit, the workspace shows **Outdated · Run again** until you recheck. Pinning a dimension or rotating the view keeps the result current.

The checks use the mesh’s shared vertex indices and apply in every model unit.

- Each triangle must have twice its area greater than 10⁻¹² times the square of its longest edge. This flags collapsed triangles and extremely thin slivers.
- Each set of three vertex indices may occur in only one face, in either winding.
- Each edge between distinct vertex indices must have exactly two incident faces. One face indicates an open boundary. Three or more indicate a non-manifold edge.
- The two faces sharing an edge must traverse it in opposite directions.

A pass covers these triangle and edge checks. Self-intersections, vertex-only contacts, inward-facing shells, wall thickness, supports, printer settings and material behavior remain outside their scope. Editable save is available now. Slicer export to Core 3MF in millimeters is specified in DEC-010 and not yet implemented.

## v1 scope

- Open STL, OBJ, and 3MF models as editable geometry and inspect them in a 3D viewport.
- Create models from descriptions and refine new or imported models through manual edits or conversation, including instructions targeting selected faces.
- Use precise dimensional controls with explicit units and optional persistent dimensions, and check geometry for 3D printing.
- Save editable models for later work. Planned slicer export writes Core 3MF in millimeters and must preserve physical dimensions.
- Use Codex, Claude, or Antigravity for conversational modeling. All three integrations are required in v1, with agent switching and model selection in Settings.

Settings route modeling requests to Codex CLI, Claude Code, or Google's Antigravity SDK. Each runs in a disposable container with operation-scoped geometry. Offline tests cover clarification, creation and whole-model revision through all three routes. Authenticated service access and interactive app use still need verification. [Provider setup, model choices and evidence](Providers/README.md)

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
- REQ-009 Export edited geometry for a slicer
