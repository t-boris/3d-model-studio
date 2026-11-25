import AppKit
import UniformTypeIdentifiers

enum UnsavedChangesChoice { case save, discard, cancel }

@MainActor
protocol WorkspaceFileDialogs {
    func confirmChanges(modelName: String, quitting: Bool) -> UnsavedChangesChoice
    func saveDestination(modelName: String) throws -> URL?
    func exportDestination(modelName: String) throws -> URL?
    func openSource() throws -> URL?
}

struct MacWorkspaceFileDialogs: WorkspaceFileDialogs {
    func confirmChanges(modelName: String, quitting: Bool) -> UnsavedChangesChoice {
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(modelName)”?"
        alert.informativeText = quitting
            ? "Your changes will be lost if you quit without saving."
            : "Your changes will be lost when another model opens."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard Changes").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }

    func saveDestination(modelName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.studioModel]
        panel.nameFieldStringValue = (modelName as NSString).deletingPathExtension
        return try selectedURL(in: panel)
    }

    func exportDestination(modelName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Core 3MF"
        panel.prompt = "Export"
        panel.allowedContentTypes = [UTType(filenameExtension: "3mf", conformingTo: .data)!]
        panel.nameFieldStringValue = (modelName as NSString).deletingPathExtension + ".3mf"
        return try selectedURL(in: panel)
    }

    func openSource() throws -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.studioModel] + ["stl", "obj", "3mf"].compactMap { UTType(filenameExtension: $0) }
        return try selectedURL(in: panel)
    }

    private func selectedURL(in panel: NSSavePanel) throws -> URL? {
        let result = panel.runModal()
        if result == .cancel { return nil }
        guard result == .OK, let url = panel.url else {
            throw MeshImportError("The file panel couldn't return a file location. Try again.")
        }
        return url
    }
}
