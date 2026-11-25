---
type: plan
feature: 3d-model-studio
title: 3D Model Studio v1 implementation and release acceptance
issues:
  - id: I-1
    title: Import and view editable models
    summary: Support opening, orbiting, zooming, and editing STL, OBJ, Core 3MF, and multipart 3MF Production models in the native viewport. Prompt for STL and OBJ source units, honor 3MF units and transforms, and preserve stable face IDs, shared vertices, and assembly occurrence mappings in the editable mesh. Verify physical placement and supported manual and conversational edits with Bambu Studio and Orca Slicer fixtures. Reject missing, invalid, cyclic, or external model-part references while preserving the active workspace.
    requirements: [REQ-002]
    decisions: [DEC-001, DEC-004, DEC-015, DEC-016]
  - id: I-2
    title: Enforce dimensions and pins in manual editing
    summary: Provide point movement, surface reshaping, planar patch extrusion, and numerical dimension controls in explicit units. Use a shared commit path to enforce operation-specific dimensions and persistent pins within the documented ±0.01 mm tolerance. Verify that users can add, change, and remove pins on new and imported models, and that a conflicting edit identifies the dimension and preserves geometry and pins.
    requirements: [REQ-003, REQ-004]
    decisions: [DEC-002, DEC-005]
  - id: I-3
    title: Create and revise models with locally verified dimensions
    summary: Support clarified creation from an empty workspace and iterative revision of new and imported models through the configured agent. Give each agent the geometry permitted for creation or whole-model revision. Document supported dimension wording, extract targets locally, ask the user to restate ambiguous targets, and report unsupported constraints. Share the dimension checks with selection edits and verify that a proposal matching the agent’s interpretation still cannot apply while a user-specified dimension remains unresolved.
    requirements: [REQ-003, REQ-005, REQ-006]
    decisions: [DEC-001, DEC-002, DEC-005, DEC-007, DEC-011]
  - id: I-4
    title: Control geometry disclosure and review selection edits
    summary: Start each selection edit with the selected faces and their boundary geometry, and require operation-specific approval before disclosing any additional parts. Compare the candidate locally with the original indexed mesh, including changes to incident unselected faces and topology. Show removed faces on the original and added faces on the candidate, require explicit confirmation for the displayed candidate when it affects unselected geometry or adds faces, and recheck requested dimensions and current pins at commit.
    requirements: [REQ-005, REQ-006]
    decisions: [DEC-005, DEC-007, DEC-009, DEC-011]
  - id: I-5
    title: Provision all three agents from the installed macOS app
    summary: Deliver an installable native macOS app with a Swift interface, in-app provisioning and authentication for Codex, Claude, and Antigravity, and agent and supported-model selection in Settings. Verify that subsequent requests use the selected configuration. On one clean Mac without Docker Desktop installed, install the app, launch it from Finder, connect all three agents through the UI without a separate Docker installation, and complete a live conversational modeling operation with each.
    requirements: [REQ-001, REQ-006]
    decisions: [DEC-003, DEC-007, DEC-013]
  - id: I-6
    title: Inspect geometry for 3D printing
    summary: Validate the indexed triangle surface for degenerate and duplicate faces, invalid edge incidence, and inconsistent winding. Report affected faces and edges in the viewport, mark results stale when geometry changes, and state the limits of the checks in the UI. Verify the inspector on new and imported models after manual and conversational edits.
    requirements: [REQ-007]
    decisions: [DEC-002, DEC-006]
  - id: I-7
    title: Save editable workspaces and protect unsaved changes
    summary: Round-trip edited geometry, face identities, units, pins, and 3MF assembly mappings in editable saves, including compatibility with existing saves and continued editing without the original import. Prompt with Save, Discard Changes, and Cancel before replacing a dirty model or quitting. Verify that save failures, canceled dialogs, and failed or canceled replacement opens preserve the active workspace and edits.
    requirements: [REQ-002, REQ-008]
    decisions: [DEC-005, DEC-006, DEC-012, DEC-015, DEC-016]
  - id: I-8
    title: Export validated Core 3MF and verify it in PrusaSlicer
    summary: Export the exact validated mesh as Core 3MF with millimeter coordinates and an explicit millimeter unit. Preserve imported assembly hierarchy and placement, including independent edits to repeated occurrences and export after reopening an editable save. Leave the destination unchanged when validation fails. Record PrusaSlicer version, scripted X/Y/Z comparisons for edited new and non-millimeter imported models, separate assembly placement checks where needed, and GUI confirmation that each acceptance export opens without rescaling.
    requirements: [REQ-009]
    decisions: [DEC-006, DEC-010, DEC-014, DEC-015, DEC-016]
updated: 2026-11-25
schema: 1
---

# Implementation plan — 3D Model Studio

## I-1: Import and view editable models

Support opening, orbiting, zooming, and editing STL, OBJ, Core 3MF, and multipart 3MF Production models in the native viewport. Prompt for STL and OBJ source units, honor 3MF units and transforms, and preserve stable face IDs, shared vertices, and assembly occurrence mappings in the editable mesh. Verify physical placement and supported manual and conversational edits with Bambu Studio and Orca Slicer fixtures. Reject missing, invalid, cyclic, or external model-part references while preserving the active workspace.

Requirements: REQ-002
Decisions: DEC-001, DEC-004, DEC-015, DEC-016

## I-2: Enforce dimensions and pins in manual editing

Provide point movement, surface reshaping, planar patch extrusion, and numerical dimension controls in explicit units. Use a shared commit path to enforce operation-specific dimensions and persistent pins within the documented ±0.01 mm tolerance. Verify that users can add, change, and remove pins on new and imported models, and that a conflicting edit identifies the dimension and preserves geometry and pins.

Requirements: REQ-003, REQ-004
Decisions: DEC-002, DEC-005

## I-3: Create and revise models with locally verified dimensions

Support clarified creation from an empty workspace and iterative revision of new and imported models through the configured agent. Give each agent the geometry permitted for creation or whole-model revision. Document supported dimension wording, extract targets locally, ask the user to restate ambiguous targets, and report unsupported constraints. Share the dimension checks with selection edits and verify that a proposal matching the agent’s interpretation still cannot apply while a user-specified dimension remains unresolved.

Requirements: REQ-003, REQ-005, REQ-006
Decisions: DEC-001, DEC-002, DEC-005, DEC-007, DEC-011

## I-4: Control geometry disclosure and review selection edits

Start each selection edit with the selected faces and their boundary geometry, and require operation-specific approval before disclosing any additional parts. Compare the candidate locally with the original indexed mesh, including changes to incident unselected faces and topology. Show removed faces on the original and added faces on the candidate, require explicit confirmation for the displayed candidate when it affects unselected geometry or adds faces, and recheck requested dimensions and current pins at commit.

Requirements: REQ-005, REQ-006
Decisions: DEC-005, DEC-007, DEC-009, DEC-011

## I-5: Provision all three agents from the installed macOS app

Deliver an installable native macOS app with a Swift interface, in-app provisioning and authentication for Codex, Claude, and Antigravity, and agent and supported-model selection in Settings. Verify that subsequent requests use the selected configuration. On one clean Mac without Docker Desktop installed, install the app, launch it from Finder, connect all three agents through the UI without a separate Docker installation, and complete a live conversational modeling operation with each.

Requirements: REQ-001, REQ-006
Decisions: DEC-003, DEC-007, DEC-013

## I-6: Inspect geometry for 3D printing

Validate the indexed triangle surface for degenerate and duplicate faces, invalid edge incidence, and inconsistent winding. Report affected faces and edges in the viewport, mark results stale when geometry changes, and state the limits of the checks in the UI. Verify the inspector on new and imported models after manual and conversational edits.

Requirements: REQ-007
Decisions: DEC-002, DEC-006

## I-7: Save editable workspaces and protect unsaved changes

Round-trip edited geometry, face identities, units, pins, and 3MF assembly mappings in editable saves, including compatibility with existing saves and continued editing without the original import. Prompt with Save, Discard Changes, and Cancel before replacing a dirty model or quitting. Verify that save failures, canceled dialogs, and failed or canceled replacement opens preserve the active workspace and edits.

Requirements: REQ-002, REQ-008
Decisions: DEC-005, DEC-006, DEC-012, DEC-015, DEC-016

## I-8: Export validated Core 3MF and verify it in PrusaSlicer

Export the exact validated mesh as Core 3MF with millimeter coordinates and an explicit millimeter unit. Preserve imported assembly hierarchy and placement, including independent edits to repeated occurrences and export after reopening an editable save. Leave the destination unchanged when validation fails. Record PrusaSlicer version, scripted X/Y/Z comparisons for edited new and non-millimeter imported models, separate assembly placement checks where needed, and GUI confirmation that each acceptance export opens without rescaling.

Requirements: REQ-009
Decisions: DEC-006, DEC-010, DEC-014, DEC-015, DEC-016
