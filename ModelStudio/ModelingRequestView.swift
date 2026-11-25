import SwiftUI

struct ModelingSheet: Identifiable {
    let id = UUID()
    let scope: ModelingScope
}

struct ModelingRequestView: View {
    let scope: ModelingScope
    @ObservedObject var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = ModelingSession()
    @State private var instruction = ""

    private var currentScope: ModelingScope {
        if scope.target == nil, !session.appliedTurns.isEmpty, let model = workspace.activeModel { return .revision(model) }
        return scope
    }

    private func send() {
        if session.question != nil {
            session.clarify(instruction)
        } else {
            session.start(scope: currentScope, instruction: instruction)
        }
        instruction = ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(currentScope.title).font(.headline)
            if let target = scope.target {
                Text("Share \(target.count) selected faces and their boundary.")
            } else if let model = currentScope.model {
                Text("Share the current geometry of \(model.name).")
            } else {
                Text("Describe the model you want to create.")
            }
            Text("Specify whole-model dimensions in units, for example “\(ConversationDimensions.example)”. Use X for width, Y for depth and Z for height.")
                .font(.caption).foregroundStyle(.secondary)
            if !session.submittedInstruction.isEmpty {
                Text(session.submittedInstruction).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            }
            if let question = session.question {
                Text(question).textSelection(.enabled)
            }
            TextField(session.question != nil ? "Your answer" : "Modeling instruction", text: $instruction, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder)
                .disabled(session.busy || session.review != nil || session.proposal != nil)
            if let review = session.review {
                Text("Share additional geometry?").font(.headline)
                if let model = scope.model {
                    ModelViewport(mesh: model.mesh, selectedFaces: review.faceIDs, selectedPoint: nil) { _, _ in }
                        .frame(height: 160)
                        .accessibilityLabel("Additional faces requested for read access")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(review.parts) { part in
                            VStack(alignment: .leading, spacing: 2) {
                                if let label = part.label { Text(label).font(.subheadline) }
                                Text("Faces \(faceList(part.faceIDs))")
                            }
                        }
                        Text(review.reason)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }.frame(maxHeight: 120)
                Text("Approval grants read access to these faces for this request.")
                HStack {
                    Button("Decline") { session.answer(review.id, allow: false) }
                    Button("Share Listed Faces") { session.answer(review.id, allow: true) }
                }
            } else if let proposal = session.proposal {
                if let original = proposal.original, let impact = proposal.impact {
                    if proposal.requiresConfirmation {
                        Text("Changes outside the selection").font(.headline)
                        Text("Orange shows faces outside your selection and new faces. Indigo shows affected selected faces.")
                    }
                    let inside = impact.affected.subtracting(impact.outside)
                    HStack {
                        reviewViewport("Original", mesh: original.mesh, highlight: impact.outside.intersection(impact.originalFaces),
                                       inside: inside.intersection(impact.originalFaces))
                        reviewViewport("Proposed", mesh: proposal.preview.mesh, highlight: impact.outside.intersection(impact.candidateFaces),
                                       inside: inside.intersection(impact.candidateFaces))
                    }
                } else {
                    reviewViewport("Proposed", mesh: proposal.preview.mesh, highlight: [])
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if let impact = proposal.impact {
                            if !impact.removed.isEmpty { Text("Removed faces · \(faceList(impact.removed.sorted()))") }
                            if !impact.added.isEmpty { Text("Added faces · \(faceList(impact.added.sorted()))") }
                            let changedOutside = impact.outside.intersection(impact.originalFaces).subtracting(impact.removed)
                            if !changedOutside.isEmpty { Text("Changed unselected faces · \(faceList(changedOutside.sorted()))") }
                        }
                        Text(session.message)
                        Text("Proposed dimensions").font(.headline)
                        ForEach(ModelDimension.allCases, id: \.self) { dimension in
                            let span = proposal.preview.extents[dimension.axis].formatted()
                            Text("\(dimension.label) · \(span) \(proposal.preview.unit.symbol)")
                        }
                        Text("Requested dimensions").font(.headline)
                        if proposal.requested.isEmpty { Text("None specified") }
                        ForEach(proposal.requested.indices, id: \.self) { i in
                            let t = proposal.requested[i]
                            Text("\(t.dimension.label) · \(t.value.formatted()) \(t.unit.symbol)")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(maxHeight: 160)
            } else if !session.message.isEmpty && session.question == nil {
                ScrollView {
                    Text(session.message).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(maxHeight: 120)
            }
            HStack {
                Button("Close") { session.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if session.busy { ProgressView().controlSize(.small) }
                if let proposal = session.proposal {
                    Button(proposal.requiresConfirmation ? "Decline Edit" : "Discard", action: session.discard)
                    if proposal.requiresConfirmation {
                        Button("Confirm Outside Changes") { apply(confirmation: proposal.id) }
                    } else {
                        Button("Apply to Model") { apply() }.keyboardShortcut(.defaultAction)
                    }
                } else {
                    Button(session.question == nil ? "Send Request" : "Send Answer", action: send)
                        .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || session.busy || session.review != nil)
                }
            }
        }
        .padding(20).frame(width: 460)
        .onDisappear { session.cancel() }
    }

    private func faceList(_ ids: [Int]) -> String {
        ids.map(String.init).joined(separator: ", ")
    }

    private func reviewViewport(_ title: String, mesh: EditableMesh, highlight: Set<Int>, inside: Set<Int> = []) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption)
            ModelViewport(mesh: mesh, selectedFaces: highlight, selectedPoint: nil, affectedSelection: inside) { _, _ in }
                .frame(height: 160).accessibilityLabel("\(title) model")
        }
    }

    private func apply(confirmation: UUID? = nil) {
        if session.apply(to: workspace, confirmedProposal: confirmation), scope.target != nil {
            dismiss()
        }
    }
}
