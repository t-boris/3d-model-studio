---
type: plan
feature: 3d-model-studio
title: 3D Model Studio v1
issues:
  - id: I-1
    title: Build the native macOS workspace
    summary: Build the native macOS application shell with a Swift UI, an active model workspace, and an entry point for settings. Verify that the application launches on macOS and opens the workspace.
    requirements: [REQ-001]
    decisions: []
  - id: I-2
    title: Import and view editable STL, OBJ, and 3MF models
    summary: Open STL, OBJ, and 3MF models in a viewport with rotation and zoom. Import each format as editable geometry in the active workspace. Use a fixture for each format to verify viewing and demonstrate one supported manual edit and one supported conversational edit.
    requirements: [REQ-002]
    decisions: [DEC-001, DEC-004]
  - id: I-3
    title: Enforce requested and pinned dimensions across edits
    summary: Define the supported dimensional measurements and numerical tolerance. Implement a shared check for explicit dimensions and units before applying geometry changes. Support pinning, changing, and unpinning dimensions on new and imported models. Verify that ordinary dimensions apply to one operation, that pinned dimensions apply to subsequent manual and AI edits, and that a violation identifies the conflicting dimension and leaves the geometry unchanged, including after confirmation of an edit outside the selection.
    requirements: [REQ-003, REQ-004, REQ-005]
    decisions: [DEC-002, DEC-005, DEC-009]
  - id: I-4
    title: Implement direct geometry editing and numerical controls
    summary: Implement direct point movement, surface reshaping, and extrusion of selected geometry within the supported v1 modeling capabilities. Let users inspect and enter supported dimensions in explicit units. Route proposed edits through the shared dimensional checks and verify the workflow on new and imported models.
    requirements: [REQ-004]
    decisions: [DEC-001, DEC-002, DEC-005]
  - id: I-5
    title: Integrate all three agents with model settings and geometry access controls
    summary: Verify a supported integration method and the required modeling workflows for Codex, Claude, and Antigravity. Add settings for choosing an agent and a model it supports, and route subsequent requests through that choice. Enforce the same geometry access rules across all three integrations. Provide the description and in-progress geometry for creation, permit access to the active model for whole-model revision, and initially supply only selected faces and boundary geometry for selection edits. Identify and explain requests for additional geometry, share only the approved parts for the current operation, and verify that approval expires and that refusal leads to limited-context continuation or an explanation.
    requirements: [REQ-006]
    decisions: [DEC-003, DEC-007]
  - id: I-6
    title: Create and revise models through conversation
    summary: Implement the conversation flow for creating a new model from a description, asking clarifying questions, and iteratively revising new or imported geometry. Use the configured agent and model, check requested dimensions and applicable pins before applying a proposal, and report unsupported dimensional constraints. Verify creation and iterative revision with each required integration.
    requirements: [REQ-003, REQ-006]
    decisions: [DEC-001, DEC-002, DEC-005, DEC-007]
  - id: I-7
    title: Apply AI edits to selected faces with review of outside changes
    summary: Let users select one or more faces and submit an instruction targeting them with any of the three agents. Review the proposed geometry before applying it to detect changes to unselected faces or their topology, including shared-vertex movement and changes needed to preserve connectivity. Highlight the affected region and require explicit confirmation before applying any such proposal. Verify that approval to access additional geometry grants no edit permission, that declining edit confirmation preserves the model, and that requested and pinned dimensions are checked even after confirmation.
    requirements: [REQ-005, REQ-006]
    decisions: [DEC-005, DEC-007, DEC-009]
  - id: I-8
    title: Validate geometry for 3D printing
    summary: Define and document the v1 geometry checks for 3D printing. Let users run them on new and imported models after manual or AI edits. Show pass or fail, the issues detected, and the affected geometry. Mark results as outdated after relevant geometry changes and explain that a passing result applies to the documented checks.
    requirements: [REQ-007]
    decisions: [DEC-002]
updated: 2026-11-25
schema: 1
---

# Implementation plan — 3D Model Studio

## I-1: Build the native macOS workspace

Build the native macOS application shell with a Swift UI, an active model workspace, and an entry point for settings. Verify that the application launches on macOS and opens the workspace.

Requirements: REQ-001

## I-2: Import and view editable STL, OBJ, and 3MF models

Open STL, OBJ, and 3MF models in a viewport with rotation and zoom. Import each format as editable geometry in the active workspace. Use a fixture for each format to verify viewing and demonstrate one supported manual edit and one supported conversational edit.

Requirements: REQ-002
Decisions: DEC-001, DEC-004

## I-3: Enforce requested and pinned dimensions across edits

Define the supported dimensional measurements and numerical tolerance. Implement a shared check for explicit dimensions and units before applying geometry changes. Support pinning, changing, and unpinning dimensions on new and imported models. Verify that ordinary dimensions apply to one operation, that pinned dimensions apply to subsequent manual and AI edits, and that a violation identifies the conflicting dimension and leaves the geometry unchanged, including after confirmation of an edit outside the selection.

Requirements: REQ-003, REQ-004, REQ-005
Decisions: DEC-002, DEC-005, DEC-009

## I-4: Implement direct geometry editing and numerical controls

Implement direct point movement, surface reshaping, and extrusion of selected geometry within the supported v1 modeling capabilities. Let users inspect and enter supported dimensions in explicit units. Route proposed edits through the shared dimensional checks and verify the workflow on new and imported models.

Requirements: REQ-004
Decisions: DEC-001, DEC-002, DEC-005

## I-5: Integrate all three agents with model settings and geometry access controls

Verify a supported integration method and the required modeling workflows for Codex, Claude, and Antigravity. Add settings for choosing an agent and a model it supports, and route subsequent requests through that choice. Enforce the same geometry access rules across all three integrations. Provide the description and in-progress geometry for creation, permit access to the active model for whole-model revision, and initially supply only selected faces and boundary geometry for selection edits. Identify and explain requests for additional geometry, share only the approved parts for the current operation, and verify that approval expires and that refusal leads to limited-context continuation or an explanation.

Requirements: REQ-006
Decisions: DEC-003, DEC-007

## I-6: Create and revise models through conversation

Implement the conversation flow for creating a new model from a description, asking clarifying questions, and iteratively revising new or imported geometry. Use the configured agent and model, check requested dimensions and applicable pins before applying a proposal, and report unsupported dimensional constraints. Verify creation and iterative revision with each required integration.

Requirements: REQ-003, REQ-006
Decisions: DEC-001, DEC-002, DEC-005, DEC-007

## I-7: Apply AI edits to selected faces with review of outside changes

Let users select one or more faces and submit an instruction targeting them with any of the three agents. Review the proposed geometry before applying it to detect changes to unselected faces or their topology, including shared-vertex movement and changes needed to preserve connectivity. Highlight the affected region and require explicit confirmation before applying any such proposal. Verify that approval to access additional geometry grants no edit permission, that declining edit confirmation preserves the model, and that requested and pinned dimensions are checked even after confirmation.

Requirements: REQ-005, REQ-006
Decisions: DEC-005, DEC-007, DEC-009

## I-8: Validate geometry for 3D printing

Define and document the v1 geometry checks for 3D printing. Let users run them on new and imported models after manual or AI edits. Show pass or fail, the issues detected, and the affected geometry. Mark results as outdated after relevant geometry changes and explain that a passing result applies to the documented checks.

Requirements: REQ-007
Decisions: DEC-002
