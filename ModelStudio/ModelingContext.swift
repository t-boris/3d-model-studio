import Foundation

enum ModelingScope {
    case creation(draft: WorkspaceModel?)
    case revision(WorkspaceModel)
    case selection(WorkspaceModel, Set<Int>)

    var model: WorkspaceModel? {
        switch self {
        case .creation(let draft): draft
        case .revision(let model), .selection(let model, _): model
        }
    }

    var title: String {
        switch self {
        case .creation: "Create Model"
        case .revision: "Revise Model"
        case .selection: "Edit Selected Faces"
        }
    }

    var target: Set<Int>? {
        if case .selection(_, let ids) = self { return ids }
        return nil
    }
}

struct ModelingClarification: Codable {
    let question: String
    let answer: String
}

struct AppliedModelingTurn: Codable {
    let instruction: String
    let clarifications: [ModelingClarification]
    let result: String
}

// Only this value crosses the provider boundary. It cannot encode a workspace,
// document name, pins, import path, unused vertices, or another sheet’s conversation.
struct ModelingInput: Encodable {
    struct Vertex: Codable {
        let id: Int
        let position: SIMD3<Double>
    }

    struct Face: Codable {
        let id: Int
        let vertices: SIMD3<Int>
    }

    let operation: String
    let instruction: String
    let clarifications: [ModelingClarification]
    let appliedTurns: [AppliedModelingTurn]
    let unit: MeshUnit
    let targetFaceIDs: [Int]?
    let readOnlyFaceIDs: [Int]
    let boundaryEdges: [[Int]]
    let vertices: [Vertex]
    let faces: [Face]

    fileprivate init(scope: ModelingScope, instruction: String, approved: Set<Int>,
                     clarifications: [ModelingClarification], appliedTurns: [AppliedModelingTurn]) throws {
        let mesh = scope.model?.mesh ?? EditableMesh()
        let target = scope.target
        let visible: [MeshFace]
        if let target {
            let allowed = target.union(approved)
            visible = mesh.faces.filter { allowed.contains($0.id) }
            guard !target.isEmpty, visible.count == allowed.count else {
                throw MeshImportError("Choose existing faces before starting a selection edit.")
            }
        } else {
            visible = mesh.faces
        }
        operation = scope.title
        self.instruction = instruction
        self.clarifications = clarifications
        self.appliedTurns = appliedTurns
        unit = scope.model?.unit ?? .millimeter
        targetFaceIDs = target?.sorted()
        readOnlyFaceIDs = approved.sorted()
        faces = visible.map { Face(id: $0.id, vertices: $0.vertices) }
        var indices = Set<Int>()
        var incidence: [[Int]: Int] = [:]
        for face in visible {
            for corner in 0..<3 {
                let vertex = face.vertices[corner]
                indices.insert(vertex)
                if target?.contains(face.id) == true {
                    let edge = [vertex, face.vertices[(corner + 1) % 3]].sorted()
                    incidence[edge, default: 0] += 1
                }
            }
        }
        boundaryEdges = incidence.filter { $0.value == 1 }.keys.sorted { $0.lexicographicallyPrecedes($1) }
        vertices = indices.sorted().map { Vertex(id: $0, position: mesh.vertices[$0]) }
    }
}

struct GeometryAccessReview: Identifiable {
    struct Part: Identifiable {
        let id: Int?
        let label: String?
        let faceIDs: [Int]
    }

    let id = UUID()
    let parts: [Part]
    let reason: String

    var faceIDs: Set<Int> { Set(parts.flatMap(\.faceIDs)) }

    init(faceIDs: Set<Int>, reason: String, assembly: ThreeMFAssembly?) {
        let ids = faceIDs.sorted()
        if let assembly {
            parts = assembly.groupByOccurrence(ids).map { index, faces in
                Part(id: index, label: index.map(assembly.occurrenceLabel), faceIDs: faces)
            }.sorted { ($0.id ?? Int.max) < ($1.id ?? Int.max) }
        } else {
            parts = [Part(id: nil, label: nil, faceIDs: ids)]
        }
        self.reason = reason
    }
}

// An indexed patch is a proposal. A later workspace transaction owns topology,
// affected-region confirmation, explicit dimensions, and pin checks.
struct AgentMeshPatch: Codable {
    let vertices: [ModelingInput.Vertex]
    let faces: [ModelingInput.Face]
    let removedFaceIDs: [Int]
    let requestedDimensions: [DimensionTarget]?
    let unsupportedConstraints: [String]?
}

enum ModelingReply {
    case access(faceIDs: [Int], acrossEdges: [[Int]], reason: String)
    case proposal(String, AgentMeshPatch)
    case question(String)
    case explanation(String)

    init(data: Data) throws {
        struct Wire: Decodable {
            let kind: String
            let message: String
            let faceIDs: [Int]?
            let acrossEdges: [[Int]]?
            let patch: AgentMeshPatch?
        }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        let message = wire.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { throw MeshImportError("The provider returned an empty message.") }
        switch wire.kind {
        case "access": self = .access(faceIDs: wire.faceIDs ?? [], acrossEdges: wire.acrossEdges ?? [], reason: message)
        case "proposal":
            guard let patch = wire.patch else { throw MeshImportError("The proposal is missing its mesh changes.") }
            self = .proposal(message, patch)
        case "question": self = .question(message)
        case "unsupported": self = .explanation("Unsupported dimensional constraint. " + message)
        case "explanation": self = .explanation(message)
        default: throw MeshImportError("The provider returned an unsupported modeling reply.")
        }
    }
}

final class ModelingOperation {
    let scope: ModelingScope
    let instruction: String
    private(set) var dimensions = ConversationDimensions()
    private let appliedTurns: [AppliedModelingTurn]
    private(set) var clarifications: [ModelingClarification] = []
    private var approved: Set<Int> = []
    private(set) var review: GeometryAccessReview?
    private(set) var ended = false

    init(scope: ModelingScope, instruction: String, appliedTurns: [AppliedModelingTurn] = []) {
        self.appliedTurns = scope.target == nil ? appliedTurns : []
        self.scope = scope
        self.instruction = instruction
        dimensions.record(instruction)
    }

    func clarify(question: String, answer: String) {
        clarifications.append(ModelingClarification(question: question, answer: answer))
        dimensions.record(answer, answering: question)
    }

    func input() throws -> ModelingInput {
        guard !ended, review == nil else { throw MeshImportError("This request is closed or awaiting approval.") }
        return try ModelingInput(scope: scope, instruction: instruction, approved: approved,
                                 clarifications: clarifications, appliedTurns: appliedTurns)
    }

    func request(faceIDs: [Int], acrossEdges: [[Int]], reason: String) throws {
        let current = try input()
        guard let target = scope.target, let mesh = scope.model?.mesh,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MeshImportError("Additional context requires a selection edit and a reason.")
        }
        let edges = Set(acrossEdges.map { $0.sorted() })
        guard edges.isSubset(of: Set(current.boundaryEdges)) else {
            throw MeshImportError("The agent requested an edge outside the selected boundary.")
        }
        var requested = Set(faceIDs)
        let existing = Set(mesh.faces.map(\.id))
        guard requested.isSubset(of: existing) else { throw MeshImportError("The agent requested an unknown face.") }
        if !edges.isEmpty {
            for face in mesh.faces where !target.contains(face.id) {
                let v = face.vertices
                if (0..<3).contains(where: { edges.contains([v[$0], v[($0 + 1) % 3]].sorted()) }) {
                    requested.insert(face.id)
                }
            }
        }
        requested.subtract(target.union(approved))
        guard !requested.isEmpty else { throw MeshImportError("There are no additional faces in that request.") }
        review = GeometryAccessReview(faceIDs: requested, reason: reason, assembly: mesh.assembly)
    }

    func resolve(_ id: UUID, allow: Bool) throws {
        guard !ended, let pending = review, pending.id == id else {
            throw MeshImportError("This access request has expired.")
        }
        review = nil
        if allow { approved.formUnion(pending.faceIDs) } else { end() }
    }

    func end() {
        ended = true
        review = nil
        approved.removeAll()
    }
}
