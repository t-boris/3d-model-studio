import SwiftUI

struct StudioSettingsView: View {
    @AppStorage(ModelingProvider.preferencesKey) private var provider = ModelingProvider.codex

    var body: some View {
        Form {
            Section("Background modeling") {
                Picker("Agent", selection: $provider) {
                    ForEach(ModelingProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                ProviderSetup(provider: provider).id(provider)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
    }
}

private struct ProviderSetup: View {
    let provider: ModelingProvider
    @AppStorage private var model: String
    @State private var key = ""
    @ObservedObject private var connections = NativeProviders.shared

    init(provider: ModelingProvider) {
        self.provider = provider
        _model = AppStorage(wrappedValue: provider.models[0], provider.modelKey)
    }

    private var keyPage: URL {
        switch provider {
        case .codex: URL(string: "https://platform.openai.com/api-keys")!
        case .claude: URL(string: "https://platform.claude.com/settings/keys")!
        case .antigravity: URL(string: "https://aistudio.google.com/apikey")!
        }
    }

    private func connect(reinstall: Bool = false) {
        let entered = key
        let route = ProviderRoute(provider: provider, model: model)
        Task {
            if await connections.connect(route, enteredKey: entered, reinstall: reinstall) { key = "" }
        }
    }

    var body: some View {
        Group {
            Picker("Model", selection: $model) {
                ForEach(provider.models, id: \.self) { Text($0).tag($0) }
            }
            Link("Get a \(provider.rawValue) API key", destination: keyPage)
            SecureField("API key", text: $key)
                .onSubmit { connect() }
            Text("Connect downloads the runtime and sends a short test to the selected model. A successful check saves the key in your Mac’s Keychain.")
                .font(.caption).foregroundStyle(.secondary)
            Text(connections.status(provider)).accessibilityLabel("Connection status. " + connections.status(provider))
            HStack {
                Button("Connect / Retry") { connect() }
                Button("Reinstall and Retry") { connect(reinstall: true) }
                Button("Disconnect") { key = ""; connections.disconnect(provider) }
            }
        }
        .disabled(connections.busy.contains(provider))
        .onAppear {
            if !provider.models.contains(model) { model = provider.models[0] }
            connections.refresh(provider)
        }
        .onChange(of: model) { _, _ in connections.refresh(provider) }
    }
}
