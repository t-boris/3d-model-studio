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
        if !session.appliedTurns.isEmpty, let model = workspace.activeModel { return .revision(model) }
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(review.reason)
                        Text("Faces " + review.faceIDs.sorted().map(String.init).joined(separator: ", "))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                }.frame(maxHeight: 80)
                Text("Approval grants read access to these faces for this request.")
                HStack {
                    Button("Decline") { session.answer(review.id, allow: false) }
                    Button("Share Listed Faces") { session.answer(review.id, allow: true) }
                }
            } else if let proposal = session.proposal {
                ModelViewport(mesh: proposal.preview.mesh, selectedFaces: [], selectedPoint: nil) { _, _ in }
                    .frame(height: 180).accessibilityLabel("Proposed model")
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
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
                    if let patch = session.patch {
                        Text("Proposed changes · \(patch.vertices.count) vertex updates, \(patch.faces.count) face updates, \(patch.removedFaceIDs.count) face removals")
                            .font(.caption)
                    }
                }.frame(maxHeight: 120)
            }
            HStack {
                Button("Close") { session.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if session.busy { ProgressView().controlSize(.small) }
                if session.proposal != nil {
                    Button("Discard", action: session.discard)
                    Button("Apply to Model") { session.apply(to: workspace) }.keyboardShortcut(.defaultAction)
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
}
