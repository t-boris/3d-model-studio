#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Interpret the production sources without starting the application.
cat ModelStudio/{EditableMesh,ModelDimensions,ManualMeshEdit,STLReader,OBJReader,ThreeMFReader,EditableModelFile,Workspace}.swift Tests/DimensionChecks.swift | xcrun swift -
