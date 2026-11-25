#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
cat ModelStudio/{EditableMesh,ModelDimensions,STLReader,OBJReader,ThreeMFReader,ModelingContext,ModelingProvider,ModelingSession}.swift Tests/ProviderChecks.swift | xcrun swift -
python3 Tests/AntigravityAdapterChecks.py
