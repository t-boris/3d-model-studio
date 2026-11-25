#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cat ModelStudio/{EditableMesh,PrintGeometry,ModelDimensions,ManualMeshEdit,STLReader,OBJReader,ThreeMFReader,EditableModelFile,WorkspaceFileDialogs,Workspace,ModelViewport}.swift Tests/ScriptedFileDialogs.swift Tests/{ManualEditChecks,PrintGeometryChecks}.swift | xcrun swift -
