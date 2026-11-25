#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cat ModelStudio/{EditableMesh,PrintGeometry,ModelDimensions,ManualMeshEdit,STLReader,OBJReader,ThreeMFReader,EditableModelFile,Workspace,ModelViewport}.swift Tests/{ManualEditChecks,PrintGeometryChecks}.swift | xcrun swift -
