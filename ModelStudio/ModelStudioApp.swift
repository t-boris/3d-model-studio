import SwiftUI

@main
struct ModelStudioApp: App {
    var body: some Scene {
        Window("3D Model Studio", id: "workspace") {
            WorkspaceView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 960, height: 640)
        .commands { WorkspaceCommands() }

        Settings {
            StudioSettingsView()
        }
    }
}
