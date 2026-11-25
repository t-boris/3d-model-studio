import SwiftUI

struct StudioSettingsView: View {
    @AppStorage(ModelingProvider.preferencesKey) private var provider = ModelingProvider.codex

    var body: some View {
        Form {
            Section("Background modeling") {
                Picker("Agent", selection: $provider) {
                    ForEach(ModelingProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                AgentModelPicker(provider: provider).id(provider)
                Text("Requests use the local provider image and \(provider.credentialName). See Providers/README.md for setup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}

private struct AgentModelPicker: View {
    let provider: ModelingProvider
    @AppStorage private var model: String

    init(provider: ModelingProvider) {
        self.provider = provider
        _model = AppStorage(wrappedValue: provider.models[0], provider.modelKey)
    }

    var body: some View {
        Picker("Model", selection: $model) {
            ForEach(provider.models, id: \.self) { Text($0).tag($0) }
        }
        .onAppear { if !provider.models.contains(model) { model = provider.models[0] } }
    }
}
