#!/bin/bash
set -euo pipefail
# An optional NEW directory keeps the exact files for PrusaSlicer acceptance.
if [[ $# -eq 1 ]]; then
    mkdir "$1"
    output=$(cd "$1" && pwd)
elif [[ $# -eq 0 ]]; then
    output=$(mktemp -d)
    trap 'rm -rf "$output"' EXIT
else
    echo "Usage: $0 [new-output-directory]" >&2
    exit 2
fi
cd "$(dirname "$0")/.."
cat ModelStudio/{EditableMesh,PrintGeometry,ModelDimensions,ManualMeshEdit,STLReader,OBJReader,ThreeMFReader,CoreThreeMFExport,EditableModelFile,WorkspaceFileDialogs,Workspace}.swift Tests/{ScriptedFileDialogs,ExportChecks}.swift | xcrun swift - "$output"
python3 Tests/PrusaComparisonChecks.py
python3 Tests/CorePackageChecks.py "$output"
