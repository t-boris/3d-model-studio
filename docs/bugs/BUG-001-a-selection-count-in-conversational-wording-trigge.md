---
type: bug
id: BUG-001
title: A selection count in conversational wording triggers a dimension restatement
status: open
severity: low
reporter: Boris Tsekinovsky
created: 2026-11-25
provenance: Created by an AI agent through MarkView
related: 3d-model-studio
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

Reproduced against the production ModelingOperation and ConversationDimensions types using interpreted Swift during I-4. The app was not launched.
