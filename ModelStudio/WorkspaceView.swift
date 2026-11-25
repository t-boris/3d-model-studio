import SwiftUI

struct WorkspaceView: View {
    @State private var activeModel = WorkspaceModel()

    var body: some View {
        ModelViewport()
            .navigationTitle(activeModel.name)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
    }
}

private struct WorkspaceModel {
    var name = "Untitled"
}

struct ModelViewport: View {
    var body: some View {
        ContentUnavailableView("No Geometry", systemImage: "cube.transparent")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .accessibilityIdentifier("modelViewport")
    }
}
