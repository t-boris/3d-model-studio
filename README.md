# 3D Model Studio

Build a native macOS application with a Swift UI for viewing, creating, and editing 3D models through both direct geometry manipulation and a conversational AI agent. Users can configure the agent and model, describe changes, and apply AI instructions to selected geometry.

## Problem

Users need a single workspace to inspect 3D files, create geometry from descriptions, and refine it through a combination of manual edits and conversational instructions.

## Scope

Proposed v1, pending confirmation: a native macOS application with a Swift UI, basic 3D viewing, conversational model creation and revision, manual geometry editing, selection-based AI edits, and agent/model settings. Use a basic visual appearance. Out of v1: advanced rendering and material authoring. The intended modeling domain, the balance between creation and imported-model editing, import coverage, and supported agent integrations remain open. Codex, Claude, and Antigravity were suggested as candidate agents, not confirmed integrations.

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
