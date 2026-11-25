---
type: bug
id: BUG-001
title: A selection count in conversational wording triggers a dimension restatement
status: fixing
severity: low
reporter: Boris Tsekinovsky
created: 2026-11-25
provenance: Created by an AI agent through MarkView
related: 3d-model-studio
updated: 2026-11-25
schema: 1
---

# A selection count in conversational wording triggers a dimension restatement

## Summary

The local dimension parser interprets “one” in “Remove one of these faces” as a length even though the instruction only counts selected faces.

## Steps to reproduce

1. Start a conversational edit with several faces selected.
2. Submit “Remove one of these faces” without a dimension.

## Expected

The app sends the scoped edit instruction to the selected route so it can propose an edit or ask which face to remove.

## Actual

The local parser asks for a final whole-model span with a unit before sending the edit instruction.

## Environment

Initially reproduced with interpreted Swift using ModelingOperation and ConversationDimensions. Reproduced interactively with ModelStudio 0.1.0 (1), macOS arm64 Debug, built from 8e0925f with Xcode 27.2.

## I-4 native reproduction

In the arm64 Debug app, create a block and choose Reshape Surface. Click the two triangles on the same side. The selection count reaches two and both triangles turn orange. Open Ask Agent → Edit Selected Faces, enter “Remove one of these faces” and click Send Request. The sheet retains the two-face scope and asks for a final whole-model span with a unit. No candidate is offered. Closing the sheet preserves the two picked faces and the original 8 vertices and 12 faces. The generated fix should also retain local restatement for a genuine ambiguous displacement such as “Move these selected faces by 2 mm”.

## Branch fix evidence

The local parser skips ordinary counts of selected faces and triangles, face IDs, and 3D or 3MF identifiers. The same regression covers ambiguous use of “in” and verifies that actual displacements still open the local restatement. All three scripted routes received the exact original two-face instruction and target IDs and produced a removal proposal. MarkView delivery is pending.
