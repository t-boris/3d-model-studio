import Foundation

enum ModelDimension: String, CaseIterable, Codable {
    case width, depth, height

    var axis: Int {
        switch self {
        case .width: 0
        case .depth: 1
        case .height: 2
        }
    }

    var label: String {
        switch self {
        case .width: "Width (X)"
        case .depth: "Depth (Y)"
        case .height: "Height (Z)"
        }
    }
}

struct DimensionTarget: Equatable, Codable {
    static let toleranceMM = 0.01
    let dimension: ModelDimension
    let value: Double
    let unit: MeshUnit

    func millimeters() throws -> Double {
        let mm = value * unit.millimetersPerUnit
        guard value >= 0, mm.isFinite else {
            throw MeshImportError("\(dimension.label) needs a finite, nonnegative length in \(unit.symbol).")
        }
        return mm
    }

    func check(extents: SIMD3<Double>, modelUnit: MeshUnit, pinned: Bool) throws {
        let target = try millimeters()
        let measured = extents[dimension.axis] * modelUnit.millimetersPerUnit
        guard measured.isFinite, measured >= target - Self.toleranceMM,
              measured <= target + Self.toleranceMM else {
            let kind = pinned ? "Pinned" : "Requested"
            throw MeshImportError("\(kind) \(dimension.label) requires \(value) \(unit.symbol). The proposal measures \(measured) mm (tolerance ±\(Self.toleranceMM) mm).")
        }
    }
}

struct WorkspaceModel: Identifiable {
    let id = UUID()
    let name: String
    let unit: MeshUnit
    private(set) var mesh = EditableMesh()
    private(set) var extents = SIMD3<Double>.zero
    private(set) var pins: [DimensionTarget] = []

    init(name: String, unit: MeshUnit, mesh: EditableMesh,
         requested: [DimensionTarget] = [], pins: [DimensionTarget] = []) throws {
        self.name = name
        self.unit = unit
        guard Set(pins.map(\.dimension)).count == pins.count else {
            throw MeshImportError("A model can have only one pin for each dimension.")
        }
        try apply(mesh, requested: requested, pins: pins)
    }

    // A geometry proposal can supply operation targets. It always inherits the current pins.
    mutating func commit(_ proposal: EditableMesh, requested: [DimensionTarget] = []) throws {
        try apply(proposal, requested: requested, pins: pins)
    }

    private mutating func apply(_ proposal: EditableMesh, requested: [DimensionTarget],
                                pins: [DimensionTarget]) throws {
        let checked = try proposal.checked()
        let (low, high) = checked.surfaceBounds
        let extents = high - low
        for dimension in ModelDimension.allCases {
            guard (extents[dimension.axis] * unit.millimetersPerUnit).isFinite else {
                throw MeshImportError("\(dimension.label) exceeds the supported numerical range.")
            }
        }
        for pin in pins { try pin.check(extents: extents, modelUnit: unit, pinned: true) }
        for target in requested { try target.check(extents: extents, modelUnit: unit, pinned: false) }
        mesh = checked
        self.extents = extents
        self.pins = pins
    }

    mutating func pinCurrent(_ dimension: ModelDimension) throws {
        guard !pins.contains(where: { $0.dimension == dimension }) else {
            throw MeshImportError("\(dimension.label) is already pinned.")
        }
        let value = extents[dimension.axis]
        let pin = DimensionTarget(dimension: dimension, value: value, unit: unit)
        try apply(mesh, requested: [], pins: pins + [pin])
    }

    mutating func unpin(_ dimension: ModelDimension) {
        pins.removeAll { $0.dimension == dimension }
    }

    // Resize about the minimum coordinate on this axis. Set leaves every pin in
    // force. Change Pin replaces just the named pin in the same transaction.
    mutating func resize(to target: DimensionTarget, changingPin: Bool = false) throws {
        var nextPins = pins
        if changingPin {
            guard let index = pins.firstIndex(where: { $0.dimension == target.dimension }) else {
                throw MeshImportError("\(target.dimension.label) has no pin to change.")
            }
            nextPins[index] = target
        }
        let length = try target.millimeters() / unit.millimetersPerUnit
        let axis = target.dimension.axis
        let (low, high) = mesh.surfaceBounds
        let span = high[axis] - low[axis]
        var proposal = mesh
        if span > 0 && span != length {
            for index in proposal.vertices.indices {
                let offset = (proposal.vertices[index][axis] - low[axis]) / span
                proposal.vertices[index][axis] = low[axis] + offset * length
            }
        }
        if changingPin {
            try apply(proposal, requested: [target], pins: nextPins)
        } else {
            try commit(proposal, requested: [target])
        }
    }

    static func newBlock() throws -> Self {
        // Start with a 10 mm block so a new workspace has measurable surfaces.
        var mesh = EditableMesh()
        mesh.vertices = [SIMD3(0, 0, 0), SIMD3(10, 0, 0), SIMD3(10, 10, 0), SIMD3(0, 10, 0),
                         SIMD3(0, 0, 10), SIMD3(10, 0, 10), SIMD3(10, 10, 10), SIMD3(0, 10, 10)]
        for (a, b, c) in [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4),
                          (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)] {
            mesh.addFace(a, b, c)
        }
        return try Self(name: "Untitled Block", unit: .millimeter, mesh: mesh)
    }
}
