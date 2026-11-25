#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cat ModelStudio/{EditableMesh,PrintGeometry,ModelDimensions,STLReader,OBJReader,ThreeMFReader,CoreThreeMFExport,ManualMeshEdit,EditableModelFile,WorkspaceFileDialogs,Workspace,ModelingContext,ConversationDimensions,ModelingProposal,ModelingProvider,ProviderRuntime,ProviderConnections,ModelingSession,ModelViewport}.swift Tests/{ProviderChecks,ProviderSetupChecks,ConversationChecks,SelectionChecks}.swift | xcrun swift -
python3 Tests/AntigravityAdapterChecks.py
python3 Tests/RuntimePackageChecks.py
