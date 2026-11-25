#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cat ModelStudio/{EditableMesh,PrintGeometry,ModelDimensions,STLReader,OBJReader,ThreeMFReader,ManualMeshEdit,EditableModelFile,WorkspaceFileDialogs,Workspace}.swift Tests/{ScriptedFileDialogs,WorkspaceFileChecks}.swift | xcrun swift -
