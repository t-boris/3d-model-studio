import SwiftUI

struct ModelingSheet: Identifiable {
    let id = UUID()
    let scope: ModelingScope
}

struct ModelingRequestView: View {
    let scope: ModelingScope
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = ModelingSession()
    @State private var instruction = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(scope.title).font(.headline)
            if let target = scope.target {
                Text("Share \(target.count) selected faces and their boundary.")
            } else if let model = scope.model {
                Text("Share the current geometry of \(model.name).")
            } else {
                Text("Describe the model you want to create.")
            }
            TextField("Modeling instruction", text: $instruction, axis: .vertical)
                .lineLimit(2...5).textFieldStyle(.roundedBorder)
                .disabled(session.busy || session.review != nil)
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
            } else if !session.message.isEmpty {
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
                Button("Send Request") { session.start(scope: scope, instruction: instruction) }
                    .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || session.busy || session.review != nil)
            }
        }
        .padding(20).frame(width: 460)
        .onDisappear { session.cancel() }
    }
}
