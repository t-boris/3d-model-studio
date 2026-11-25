import Combine
import Foundation
import Security

protocol ProviderCredentials {
    func read(_ provider: ModelingProvider) throws -> String?
    func save(_ key: String, for provider: ModelingProvider) throws
    func remove(_ provider: ModelingProvider) throws
}

struct KeychainCredentials: ProviderCredentials {
    private func item(_ provider: ModelingProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.github.t-boris.3d-model-studio.providers",
         kSecAttrAccount as String: provider.rawValue]
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw MeshImportError("Keychain access failed (\(status)). Unlock your login keychain, allow access and retry.")
        }
    }

    func read(_ provider: ModelingProvider) throws -> String? {
        var query = item(provider)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw MeshImportError("The saved credential is unreadable. Enter a replacement API key.")
        }
        return key
    }

    func save(_ key: String, for provider: ModelingProvider) throws {
        var query = item(provider)
        let value = Data(key.utf8)
        let update = [kSecValueData as String: value]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = value
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            try check(SecItemAdd(query as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    func remove(_ provider: ModelingProvider) throws {
        let status = SecItemDelete(item(provider) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }
}

@MainActor
final class NativeProviders: ObservableObject, ProviderTransport {
    static let shared = NativeProviders()
    private let runtime: NativeRuntime
    private let credentials: ProviderCredentials
    private let process: ProviderProcess

    @Published private(set) var busy: Set<ModelingProvider> = []
    @Published private var messages: [ModelingProvider: String] = [:]

    init(runtime: NativeRuntime = NativeRuntime(), credentials: ProviderCredentials = KeychainCredentials()) {
        self.runtime = runtime
        self.credentials = credentials
        process = ProviderProcess(profile: runtime.resources.appendingPathComponent("turn.sb"))
    }

    func refresh(_ provider: ModelingProvider) {
        guard !busy.contains(provider) else { return }
        do {
            if runtime.installed(provider) == nil {
                messages[provider] = "Runtime required. Connect to download it."
            } else if try credentials.read(provider) == nil {
                messages[provider] = "Runtime installed. Enter an API key to connect."
            } else {
                messages[provider] = "Key saved. Check the connection to verify access to this model."
            }
        } catch { messages[provider] = error.localizedDescription }
    }

    func status(_ provider: ModelingProvider) -> String { messages[provider] ?? "Ready for setup." }

    @discardableResult
    func connect(_ route: ProviderRoute, enteredKey: String, reinstall: Bool = false) async -> Bool {
        let provider = route.provider
        guard busy.insert(provider).inserted else { return false }
        defer { busy.remove(provider) }
        do {
            let entered = enteredKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = try entered.isEmpty ? credentials.read(provider) : entered
            guard let key, !key.isEmpty else { throw MeshImportError("Enter a \(provider.rawValue) API key and choose Connect.") }
            messages[provider] = "Preparing \(provider.rawValue)…"
            let installation = try await runtime.provision(provider, reinstall: reinstall)
            messages[provider] = "Checking access to \(route.model)…"
            let marker = "STUDIO-" + UUID().uuidString
            let probe = Data("Reply with exactly this text and nothing else: \(marker)".utf8)
            let reply = try await process.invoke(installation, route: route, key: key, input: probe)
            guard String(decoding: reply, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == marker else {
                throw MeshImportError("Unexpected connection reply. Check model access and retry.")
            }
            if !entered.isEmpty { try credentials.save(key, for: provider) }
            messages[provider] = "Connected to \(provider.rawValue) · \(route.model)."
            return true
        } catch {
            messages[provider] = error.localizedDescription
            return false
        }
    }

    func disconnect(_ provider: ModelingProvider) {
        guard !busy.contains(provider) else { return }
        do {
            try credentials.remove(provider)
            messages[provider] = "Disconnected. Enter a key to reconnect."
        } catch { messages[provider] = error.localizedDescription }
    }

    func run(route: ProviderRoute, input: Data) async throws -> Data {
        let provider = route.provider
        do {
            guard let installation = runtime.installed(provider), let key = try credentials.read(provider) else {
                throw MeshImportError("Open Settings and connect \(provider.rawValue), then retry your request.")
            }
            return try await process.invoke(installation, route: route, key: key, input: input)
        } catch {
            if !(error is CancellationError), !busy.contains(provider) { messages[provider] = error.localizedDescription }
            throw error
        }
    }
}
