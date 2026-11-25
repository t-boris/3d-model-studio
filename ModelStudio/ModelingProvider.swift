import Foundation

enum ModelingProvider: String, CaseIterable {
    case codex = "Codex"
    case claude = "Claude"
    case antigravity = "Antigravity"

    var models: [String] {
        switch self {
        case .codex: ["gpt-6.2-sol", "gpt-6.2-astra"]
        case .claude: ["sonnet", "opus"]
        case .antigravity: ["gemini-4-hydrogen", "gemini-3.8-flash"]
        }
    }

    var credentialName: String {
        switch self {
        case .codex: "CODEX_API_KEY"
        case .claude: "ANTHROPIC_API_KEY"
        case .antigravity: "GEMINI_API_KEY"
        }
    }

    func arguments(model: String, in directory: URL) -> [String] {
        switch self {
        case .codex:
            ["exec", "--model", model, "--ephemeral", "--skip-git-repo-check",
             "--sandbox", "read-only", "--ignore-user-config", "--ignore-rules",
             "--disable", "shell_tool", "--disable", "computer_use", "--disable", "multi_agent",
             "--disable", "plugins", "--disable", "hooks", "-c", "web_search=\"disabled\"", "-"]
        case .claude:
            ["--print", "--model", model, "--bare", "--tools", "",
             "--no-session-persistence", "--disable-slash-commands", "--strict-mcp-config",
             "--mcp-config", "{\"mcpServers\":{}}", "--output-format", "text"]
        case .antigravity:
            ["-I", directory.appendingPathComponent("antigravity.py").path, model]
        }
    }

    static let preferencesKey = "modeling.provider"
    var modelKey: String { "modeling.model." + rawValue }
}

struct ProviderRoute {
    let provider: ModelingProvider
    let model: String

    init(defaults: UserDefaults = .standard) {
        let provider = defaults.string(forKey: ModelingProvider.preferencesKey)
            .flatMap(ModelingProvider.init(rawValue:)) ?? .codex
        self.provider = provider
        let saved = defaults.string(forKey: provider.modelKey)
        model = saved.flatMap { provider.models.contains($0) ? $0 : nil } ?? provider.models[0]
    }

    init(provider: ModelingProvider, model: String) {
        self.provider = provider
        self.model = provider.models.contains(model) ? model : provider.models[0]
    }

    func arguments(in directory: URL) -> [String] { provider.arguments(model: model, in: directory) }

    func send(_ input: ModelingInput, transport: ProviderTransport) async throws -> ModelingReply {
        let header = """
        You are the background modeling agent in 3D Model Studio. Use the indexed surface below.
        Coordinates are XYZ triples in the supplied unit. targetFaceIDs is the authorized selection.
        readOnlyFaceIDs are context only. Return exactly one JSON object without Markdown.
        appliedTurns describes earlier accepted edits for context. Only the current instruction and its
        clarifications set operation targets. Ask a focused question when the shape, dimension or unit is unclear:
        {"kind":"question","message":"What height and unit should the block have?"}. Use the answers on this request.
        For an edit return {"kind":"proposal","message":"description","patch":{"vertices":[],"faces":[],"removedFaceIDs":[],"requestedDimensions":[],"unsupportedConstraints":[]}}.
        List only new or changed items. Vertices have id and position; triangular faces have id and vertices.
        Preserve existing IDs; assign negative temporary IDs to new items. For creation propose the initial mesh.
        For a selection edit you may instead request specific additional faces by ID or faces across a supplied
        boundary edge: {"kind":"access","message":"specific reason","faceIDs":[],"acrossEdges":[[a,b]]}.
        When geometryAccessDenied is true, the user declined additional geometry. Continue using only the
        supplied geometry, or explain why you cannot proceed. Do not request more geometry in this operation.
        Every patch must include both constraint arrays, even when empty. In requestedDimensions,
        list every requested or explicitly preserved whole-model span, e.g. {"dimension":"height","value":7,"unit":"millimeter"}.
        dimension is width (X), depth (Y) or height (Z). unit is micron, millimeter, centimeter, meter, inch or foot.
        Follow user restatements such as “final span along X is 30 mm”. The app verifies user targets locally.
        Keep requested lengths in their explicit units. Convert coordinates to the input mesh unit.
        If a dimensional constraint (e.g. a hole diameter, angle or wall thickness) cannot be checked as one of
        those spans, return {"kind":"unsupported","message":"identify the constraint and explain why"}.
        Never omit an unsupported constraint to propose a partial edit. For other failures use kind "explanation".
        """
        var payload = Data((header + "\n").utf8)
        payload.append(try JSONEncoder().encode(input))
        let reply = try await transport.run(route: self, input: payload)
        do { return try ModelingReply(data: reply) }
        catch let DecodingError.dataCorrupted(context) where context.codingPath.contains(where: { $0.stringValue == "requestedDimensions" }) {
            throw MeshImportError("Unsupported dimensional constraint or unit. Use whole-model width, depth or height in a supported length unit.")
        } catch is DecodingError {
            throw MeshImportError("\(provider.rawValue) returned an invalid modeling reply. Request a new proposal.")
        }
    }
}

protocol ProviderTransport {
    func run(route: ProviderRoute, input: Data) async throws -> Data
}
