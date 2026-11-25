import Foundation
import simd

/// Checks the active indexed surface. WorkspaceModel already enforces valid indices and finite extents.
struct PrintGeometryReport {
    enum Problem: String {
        case degenerate = "Collapsed or sliver triangle"
        case duplicate = "Duplicate triangles"
        case boundary = "Open boundary edge"
        case nonManifold = "Edge shared by more than two faces"
        case winding = "Inconsistent face winding"

        var guidance: String {
            switch self {
            case .degenerate: "Move the corners apart to give this triangle area."
            case .duplicate: "Keep one triangle for this set of corners."
            case .boundary: "Close the gap or join the adjoining faces along this edge."
            case .nonManifold: "Separate or remove extra faces so exactly two meet at this edge."
            case .winding: "Reverse the winding on one side so the two faces traverse this edge in opposite directions."
            }
        }
    }

    struct Issue {
        let problem: Problem
        let faces: [Int]
        let edge: SIMD2<Int>?
        let markerVertex: Int

        var location: String {
            if let edge { return "Edge \(edge.x)–\(edge.y)" }
            return "Face \(faces[0])"
        }
    }

    let issues: [Issue]
    var passed: Bool { issues.isEmpty }

    init(mesh: EditableMesh) {
        struct EdgeUse {
            let face: Int
            let forward: Bool
        }

        var issues: [Issue] = []
        var triangles: [SIMD3<Int>: [Int]] = [:]
        var edges: [SIMD2<Int>: [EdgeUse]] = [:]
        for face in mesh.faces {
            let v = face.vertices
            if Self.isDegenerate(mesh.vertices[v.x], mesh.vertices[v.y], mesh.vertices[v.z]) {
                issues.append(Issue(problem: .degenerate, faces: [face.id], edge: nil, markerVertex: v.x))
            }
            let sorted = [v.x, v.y, v.z].sorted()
            triangles[SIMD3(sorted[0], sorted[1], sorted[2]), default: []].append(face.id)
            for i in 0..<3 {
                let a = v[i], b = v[(i + 1) % 3]
                let edge = SIMD2(min(a, b), max(a, b))
                // A folded triangle can visit the same edge twice. Count distinct faces.
                if a != b && edges[edge]?.last?.face != face.id {
                    edges[edge, default: []].append(EdgeUse(face: face.id, forward: a < b))
                }
            }
        }
        for (corners, faces) in triangles where faces.count > 1 {
            issues.append(Issue(problem: .duplicate, faces: faces.sorted(), edge: nil, markerVertex: corners.x))
        }
        for (edge, uses) in edges {
            let problem: Problem
            switch uses.count {
            case 1: problem = .boundary
            case 2 where uses[0].forward == uses[1].forward: problem = .winding
            case 2: continue
            default: problem = .nonManifold
            }
            issues.append(Issue(problem: problem, faces: uses.map(\.face).sorted(), edge: edge, markerVertex: edge.x))
        }
        self.issues = issues.sorted {
            if $0.faces[0] != $1.faces[0] { return $0.faces[0] < $1.faces[0] }
            if $0.problem != $1.problem { return $0.problem.rawValue < $1.problem.rawValue }
            guard let a = $0.edge, let b = $1.edge else { return false }
            return a.x == b.x ? a.y < b.y : a.x < b.x
        }
    }

    private static func isDegenerate(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Bool {
        let ab = b - a, ac = c - a, bc = c - b
        let scale = max(simd_abs(ab).max(), simd_abs(ac).max(), simd_abs(bc).max())
        guard scale > 0 else { return true }
        // Scale before taking products so the relative test works across model units and magnitudes.
        let u = ab / scale, v = ac / scale, w = bc / scale
        let longestSquared = max(simd_length_squared(u), simd_length_squared(v), simd_length_squared(w))
        return simd_length(simd_cross(u, v)) <= 1e-12 * longestSquared
    }
}

enum PrintValidationState {
    case unchecked, checking(UUID), current(PrintGeometryReport), stale

    var label: String {
        switch self {
        case .unchecked: "Unchecked"
        case .checking: "Checking…"
        case .current(let report): report.passed ? "Pass" : "Fail · \(report.issues.count) \(report.issues.count == 1 ? "issue" : "issues")"
        case .stale: "Outdated · Run again"
        }
    }
}
