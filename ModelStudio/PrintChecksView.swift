import SwiftUI

struct PrintChecksView: View {
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Print Geometry Checks").font(.title2)
            Text("Checks triangle area, duplicate triangles, edge closure and shared-edge winding. A pass covers these checks only. Self-intersections, shell direction, wall thickness, printer settings and materials are outside their scope.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(workspace.printValidation.label)
                    .font(.headline)
                    .accessibilityIdentifier("printCheckResult")
                Spacer()
                if case .checking = workspace.printValidation {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Run Checks") { Task { await workspace.validatePrintGeometry() } }
                        .keyboardShortcut(.defaultAction)
                }
            }
            if case .current(let report) = workspace.printValidation {
                if report.passed {
                    Label("All triangles and shared edges passed.", systemImage: "checkmark.circle")
                } else if let model = workspace.activeModel {
                    PrintIssueInspector(mesh: model.mesh, issues: report.issues)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(minWidth: 580, idealWidth: 680, minHeight: 410, idealHeight: 470)
    }
}

private struct PrintIssueInspector: View {
    let mesh: EditableMesh
    let issues: [PrintGeometryReport.Issue]
    @State private var selection: Int? = 0

    var body: some View {
        let index = selection ?? 0
        let issue = issues[issues.indices.contains(index) ? index : 0]
        HStack {
            List(issues.indices, id: \.self, selection: $selection) { index in
                VStack(alignment: .leading) {
                    Text(issues[index].problem.rawValue)
                    Text(issues[index].location).font(.caption)
                }
                .tag(index)
            }
            .frame(minWidth: 180, idealWidth: 220)
            ModelViewport(mesh: mesh, selectedFaces: Set(issue.faces), selectedPoint: issue.markerVertex,
                          inspectionEdge: issue.edge, inspectingIssue: true) { _, _ in }
                .accessibilityLabel("Affected faces for \(issue.location)")
                .frame(minWidth: 220)
        }
        Text(issue.problem.guidance)
        ScrollView(.horizontal) {
            Text("Highlighted face IDs · " + issue.faces.map(String.init).joined(separator: ", "))
                .font(.caption.monospacedDigit())
                .textSelection(.enabled)
        }
    }
}
