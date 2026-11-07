import Foundation
import Security

/// User settings. The token lives in the Keychain, everything else in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let retentionChoices = [3, 6, 12]

    @Published var serverURLString: String {
        didSet { defaults.set(serverURLString, forKey: Keys.serverURL) }
    }
    @Published var token: String {
        didSet { Keychain.save(token, account: Keys.token) }
    }
    @Published var retentionMonths: Int {
        didSet { defaults.set(retentionMonths, forKey: Keys.retention) }
    }
    @Published var tier: SafetyTier {
        didSet { defaults.set(tier.rawValue, forKey: Keys.tier) }
    }
    @Published var autoArchive: Bool {
        didSet { defaults.set(autoArchive, forKey: Keys.autoArchive) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let serverURL = "serverURL"
        static let token = "token"
        static let retention = "retentionMonths"
        static let tier = "tier"
        static let autoArchive = "autoArchive"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        serverURLString = defaults.string(forKey: Keys.serverURL) ?? ""
        token = Keychain.load(account: Keys.token) ?? ""
        let storedRetention = defaults.integer(forKey: Keys.retention)
        retentionMonths = Self.retentionChoices.contains(storedRetention) ? storedRetention : 6
        tier = defaults.string(forKey: Keys.tier).flatMap(SafetyTier.init(rawValue:)) ?? .casual
        autoArchive = defaults.bool(forKey: Keys.autoArchive)
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let url = env["PHOTOPLUS_SERVER_URL"] { serverURLString = url }
        if let value = env["PHOTOPLUS_TOKEN"] { token = value }
        #endif
    }

    /// The client for the configured NAS, or nil until an http(s) address and a token are set.
    var apiClient: ApiClient? {
        let trimmed = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil, !token.isEmpty else {
            return nil
        }
        return ApiClient(baseURL: url, token: token)
    }
}

private enum Keychain {
    private static func query(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.yahaa.photoplus",
         kSecAttrAccount as String: account]
    }

    static func load(account: String) -> String? {
        var request = query(account: account)
        request[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(bytes: data, encoding: .utf8)
    }

    static func save(_ value: String, account: String) {
        SecItemDelete(query(account: account) as CFDictionary)
        guard !value.isEmpty else { return }
        var request = query(account: account)
        request[kSecValueData as String] = Data(value.utf8)
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(request as CFDictionary, nil)
    }
}
