#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cat ModelStudio/{EditableMesh,PrintGeometry,ModelDimensions,STLReader,OBJReader,ThreeMFReader,ManualMeshEdit,EditableModelFile,Workspace,ModelingContext,ConversationDimensions,ModelingProposal,ModelingProvider,ModelingSession,ModelViewport}.swift Tests/{ProviderChecks,ConversationChecks,SelectionChecks}.swift | xcrun swift -
python3 Tests/AntigravityAdapterChecks.py
