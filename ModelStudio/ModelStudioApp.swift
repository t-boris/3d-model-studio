import SwiftUI

@MainActor
final class StudioAppDelegate: NSObject, NSApplicationDelegate {
    let workspace = Workspace()
    private var terminationPending = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminationPending { return .terminateLater }
        guard workspace.canStartFileOperation else { return .terminateCancel }
        guard workspace.hasUnsavedChanges else { return .terminateNow }
        terminationPending = true
        Task {
            let proceed = await workspace.shouldQuit()
            terminationPending = false
            sender.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }
}

@main
struct ModelStudioApp: App {
    @NSApplicationDelegateAdaptor(StudioAppDelegate.self) private var delegate

    var body: some Scene {
        Window("3D Model Studio", id: "workspace") {
            WorkspaceView(workspace: delegate.workspace)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 960, height: 640)
        .commands { WorkspaceCommands() }

        Settings {
            StudioSettingsView()
        }
    }
}
