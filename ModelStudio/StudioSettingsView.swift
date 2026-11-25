import SwiftUI

struct StudioSettingsView: View {
    var body: some View {
        Form {
            Section("Agents") {
                Text("Agent and model selection will be available when integrations are ready.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
