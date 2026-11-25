import Foundation

struct STLReader {
    private var mesh = EditableMesh()
    private var vertexIndices: [SIMD3<Double>: Int] = [:]

    static func read(_ data: Data) throws -> EditableMesh {
        var reader = Self()
        // Binary headers can also begin with "solid". The count fixes the exact size.
        if data.count >= 84 {
            let count = data.withUnsafeBytes { bytes in
                Int(UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: 80, as: UInt32.self)))
            }
            if data.count == 84 + 50 * count {
                try reader.readBinary(data, count: count)
                return reader.mesh
            }
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw MeshImportError("The binary STL length does not match its triangle count. Export the complete file again.")
        }
        try reader.readASCII(text)
        return reader.mesh
    }

    private mutating func index(_ position: SIMD3<Double>) -> Int {
        if let existing = vertexIndices[position] { return existing }
        let index = mesh.vertices.count
        mesh.vertices.append(position)
        vertexIndices[position] = index
        return index
    }

    private mutating func readBinary(_ data: Data, count: Int) throws {
        try data.withUnsafeBytes { bytes in
            func position(at offset: Int) throws -> SIMD3<Double> {
                func coordinate(_ axis: Int) -> Double {
                    let bits = bytes.loadUnaligned(fromByteOffset: offset + axis * 4, as: UInt32.self)
                    return Double(Float(bitPattern: UInt32(littleEndian: bits)))
                }
                let point = SIMD3(coordinate(0), coordinate(1), coordinate(2))
                guard point.x.isFinite, point.y.isFinite, point.z.isFinite else {
                    throw MeshImportError("The binary STL contains an invalid vertex. Repair the mesh and export again.")
                }
                return point
            }

            for triangle in 0..<count {
                let offset = 84 + 50 * triangle + 12
                let a = try index(position(at: offset))
                let b = try index(position(at: offset + 12))
                let c = try index(position(at: offset + 24))
                mesh.addFace(a, b, c)
            }
        }
    }

    private enum Stage { case solid, facet, loop, vertex, endLoop, endFacet }

    private mutating func readASCII(_ text: String) throws {
        var stage = Stage.solid
        var corners: [Int] = []
        for (lineIndex, line) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let words = line.split(whereSeparator: \.isWhitespace)
            guard let first = words.first else { continue }
            switch (stage, first.lowercased()) {
            case (.solid, "solid"):
                stage = .facet
            case (.facet, "endsolid"):
                stage = .solid
            case (.facet, "facet") where words.count == 5 && words[1].lowercased() == "normal":
                corners.removeAll(keepingCapacity: true)
                stage = .loop
            case (.loop, "outer") where words.count == 2 && words[1].lowercased() == "loop":
                stage = .vertex
            case (.vertex, "vertex") where words.count == 4:
                let xyz = words.dropFirst().compactMap { Double($0) }
                guard xyz.count == 3, xyz.allSatisfy(\.isFinite) else {
                    throw MeshImportError("Invalid STL vertex on line \(lineIndex + 1). Enter three finite coordinates.")
                }
                corners.append(index(SIMD3(xyz[0], xyz[1], xyz[2])))
                if corners.count == 3 { stage = .endLoop }
            case (.endLoop, "endloop"):
                stage = .endFacet
            case (.endFacet, "endfacet"):
                mesh.addFace(corners[0], corners[1], corners[2])
                stage = .facet
            default:
                throw MeshImportError("Unexpected STL record on line \(lineIndex + 1). Export an ASCII or binary triangle mesh.")
            }
        }
        guard stage == .solid else {
            throw MeshImportError("The STL ends before its solid is complete. Export the full mesh again.")
        }
    }
}
