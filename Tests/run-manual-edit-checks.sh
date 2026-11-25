#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cat ModelStudio/{EditableMesh,ModelDimensions,ManualMeshEdit,STLReader,OBJReader,ThreeMFReader,EditableModelFile,Workspace,ModelViewport}.swift Tests/ManualEditChecks.swift | xcrun swift -
