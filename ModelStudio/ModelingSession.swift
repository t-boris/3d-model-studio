import Combine
import Foundation

@MainActor
final class ModelingSession: ObservableObject {
    @Published private(set) var review: GeometryAccessReview?
    @Published private(set) var message = ""
    @Published private(set) var busy = false
    @Published private(set) var patch: AgentMeshPatch?

    private var operation: ModelingOperation?
    private var route: ProviderRoute?
    private var task: Task<Void, Never>?
    private let transport: ProviderTransport

    init(transport: ProviderTransport = DockerTransport()) { self.transport = transport }

    func start(scope: ModelingScope, instruction: String, defaults: UserDefaults = .standard) {
        cancel()
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { message = "Enter a modeling instruction."; return }
        operation = ModelingOperation(scope: scope, instruction: instruction)
        route = ProviderRoute(defaults: defaults)
        dispatch()
    }

    func answer(_ id: UUID, allow: Bool) {
        guard let review, review.id == id else { return }
        do {
            try operation?.resolve(id, allow: allow)
            self.review = nil
            if allow {
                dispatch()
            } else {
                finish("The agent requested those faces because: \(review.reason) Access was declined. The request ended with the available geometry.")
            }
        } catch { finish(error.localizedDescription) }
    }

    func cancel() {
        task?.cancel()
        finish("")
        patch = nil
    }

    private func finish(_ result: String) {
        operation?.end()
        operation = nil
        review = nil
        route = nil
        task = nil
        busy = false
        message = result
    }

    private func dispatch() {
        guard let operation, let route else { return }
        do {
            let input = try operation.input()
            busy = true
            message = "Waiting for \(route.provider.rawValue) · \(route.model)…"
            task = Task {
                do {
                    let reply = try await route.send(input, transport: transport)
                    try Task.checkCancellation()
                    busy = false
                    switch reply {
                    case let .access(ids, edges, reason):
                        try self.operation?.request(faceIDs: ids, acrossEdges: edges, reason: reason)
                        review = self.operation?.review
                        message = ""
                    case let .proposal(summary, changes):
                        patch = changes
                        finish(summary)
                    case let .explanation(text):
                        finish(text)
                    }
                } catch {
                    if !Task.isCancelled { finish(error.localizedDescription) }
                }
            }
        } catch { finish(error.localizedDescription) }
    }
}
