import Combine
import Foundation

@MainActor
final class ModelingSession: ObservableObject {
    @Published private(set) var review: GeometryAccessReview?
    @Published private(set) var message = ""
    @Published private(set) var busy = false
    @Published private(set) var patch: AgentMeshPatch?

    @Published private(set) var submittedInstruction = ""
    @Published private(set) var question: String?
    @Published private(set) var proposal: ModelingProposal?
    @Published private(set) var appliedTurns: [AppliedModelingTurn] = []
    private var lastApplied: WorkspaceModel?
    private var pendingTurn: AppliedModelingTurn?

    private var operation: ModelingOperation?
    private var route: ProviderRoute?
    private var task: Task<Void, Never>?
    private let transport: ProviderTransport

    init(transport: ProviderTransport = DockerTransport()) { self.transport = transport }

    func start(scope: ModelingScope, instruction: String, defaults: UserDefaults = .standard) {
        let continues = scope.target == nil && lastApplied != nil && scope.model?.id == lastApplied?.id
            && scope.model?.mesh == lastApplied?.mesh
        if !continues { appliedTurns = []; lastApplied = nil }
        task?.cancel()
        finish("")
        proposal = nil
        patch = nil
        pendingTurn = nil
        let instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { message = "Enter a modeling instruction."; return }
        submittedInstruction = instruction
        operation = ModelingOperation(scope: scope, instruction: instruction, appliedTurns: appliedTurns)
        route = ProviderRoute(defaults: defaults)
        dispatch()
    }

    func clarify(_ text: String) {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let operation, let question, !answer.isEmpty else { return }
        operation.clarify(question: question, answer: answer)
        self.question = nil
        dispatch()
    }

    func apply(to workspace: Workspace) {
        guard let proposal, let pendingTurn else { return }
        do {
            try proposal.apply(to: workspace)
            lastApplied = workspace.activeModel
            appliedTurns.append(pendingTurn)
            message = "Applied. " + pendingTurn.result
        } catch { message = error.localizedDescription }
        self.proposal = nil
        self.pendingTurn = nil
        patch = nil
    }

    func discard() {
        proposal = nil
        pendingTurn = nil
        patch = nil
        message = "Proposal discarded."
    }

    func answer(_ id: UUID, allow: Bool) {
        guard let review, review.id == id else { return }
        do {
            try operation?.resolve(id, allow: allow)
            self.review = nil
            if allow {
                dispatch()
            } else {
                finish("Access declined. The agent requested these faces for the following reason. \(review.reason) The request has ended.")
            }
        } catch { finish(error.localizedDescription) }
    }

    func cancel() {
        task?.cancel()
        finish("")
        patch = nil
        proposal = nil
        pendingTurn = nil
        appliedTurns = []
        lastApplied = nil
    }

    private func finish(_ result: String) {
        operation?.end()
        operation = nil
        question = nil
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
                        if operation.scope.target == nil {
                            proposal = try ModelingProposal(operation: operation, patch: changes)
                            pendingTurn = AppliedModelingTurn(instruction: operation.instruction,
                                                              clarifications: operation.clarifications, result: summary)
                        }
                        patch = changes
                        finish(summary)
                    case let .question(text):
                        question = text
                        message = text
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
