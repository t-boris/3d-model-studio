#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cases=$(mktemp -d)
trap 'rm -rf "$cases"' EXIT
python3 Tests/assembly-errors.py "$cases"
cat ModelStudio/{EditableMesh,PrintGeometry,ModelDimensions,STLReader,OBJReader,ThreeMFReader,CoreThreeMFExport,ManualMeshEdit,EditableModelFile,WorkspaceFileDialogs,Workspace,ModelingContext,ConversationDimensions,ModelingProposal,ModelViewport}.swift Tests/ScriptedFileDialogs.swift Tests/AssemblyChecks.swift | xcrun swift - "$cases"
