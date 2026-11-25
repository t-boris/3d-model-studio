import Foundation

@MainActor
final class ScriptedFileDialogs: WorkspaceFileDialogs {
    var choice: UnsavedChangesChoice
    var destination: URL?
    var source: Result<URL?, Error> = .success(nil)
    var events: [String] = []
    var onPick: (() throws -> Void)?

    init(choice: UnsavedChangesChoice) { self.choice = choice }

    func confirmChanges(modelName: String, quitting: Bool) -> UnsavedChangesChoice {
        events.append(quitting ? "confirm quit" : "confirm open")
        return choice
    }

    func saveDestination(modelName: String) -> URL? {
        events.append("save")
        return destination
    }

    func exportDestination(modelName: String) throws -> URL? {
        events.append("export")
        try onPick?()
        return destination
    }

    func openSource() throws -> URL? {
        events.append("open")
        try onPick?()
        return try source.get()
    }
}
