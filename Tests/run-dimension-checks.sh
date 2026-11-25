#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Interpret the production sources without starting the application.
cat ModelStudio/{EditableMesh,PrintGeometry,ModelDimensions,ManualMeshEdit,STLReader,OBJReader,ThreeMFReader,EditableModelFile,WorkspaceFileDialogs,Workspace}.swift Tests/ScriptedFileDialogs.swift Tests/DimensionChecks.swift | xcrun swift -
