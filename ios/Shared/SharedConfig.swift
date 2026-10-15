import Foundation
import Security

/// What the share extension needs to know about the paired computer.
///
/// An extension is a separate process with its own container, so it cannot read the
/// app's own UserDefaults or Keychain. The app publishes the non-secret details into
/// the shared App Group and keeps the pairing token in a shared Keychain access
/// group — the token stays encrypted in the Keychain, accessible after the first
/// unlock for notification replies, rather than being copied into a plist beside it.
enum SharedConfig {
    /// Set only by the single-app ESign packaging step.
    static var isStandalone: Bool {
        Bundle.main.object(forInfoDictionaryKey: "TethrXStandalone") as? Bool ?? false
    }

    static let appGroup = "group.com.tethrx.app"
    private static let bridgesKey = "shared.bridges"
    private static let activeKey = "shared.activeBridgeId"

    /// A paired computer, minus its token.
    struct Bridge: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var address: String
        var pin: String?
        var tokenAccount: String { "bridge.token." + id }
    }

    private static var defaults: UserDefaults? {
        guard !isStandalone else { return nil }
        return UserDefaults(suiteName: appGroup)
    }

    /// Called by the app whenever its bridge list changes.
    static func publish(bridges: [Bridge], activeId: String?) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(bridges) {
            defaults.set(data, forKey: bridgesKey)
        }
        defaults.set(activeId, forKey: activeKey)
    }

    static func bridges() -> [Bridge] {
        guard let data = defaults?.data(forKey: bridgesKey),
              let list = try? JSONDecoder().decode([Bridge].self, from: data) else { return [] }
        return list
    }

    static func activeBridge() -> Bridge? {
        let list = bridges()
        if let id = defaults?.string(forKey: activeKey), let match = list.first(where: { $0.id == id }) {
            return match
        }
        return list.first
    }

    /// The pairing token for a bridge, from the shared Keychain group.
    static func token(for bridge: Bridge) -> String? {
        SharedKeychain.load(account: bridge.tokenAccount)
    }
}

/// Keychain access scoped to the group both the app and its extensions can reach.
enum SharedKeychain {
    static let service = "com.tethrx.app"

    /// Keychain access groups are matched as EXACT strings against the entitlement,
    /// normally `$(AppIdentifierPrefix)group.com.tethrx.app`. Resolve the prefix
    /// from build settings in each bundle's Info.plist, including the extension.
    private static var accessGroups: [String] {
        guard !SharedConfig.isStandalone else { return [] }
        var groups: [String] = []
        if let group = Bundle.main.object(forInfoDictionaryKey: "TethrXSharedKeychainGroup") as? String,
           !group.isEmpty, !group.contains("$(") {
            groups.append(group)
        }
        // Older TrollStore packages use the unprefixed entitlement.
        groups.append("group.com.tethrx.app")
        return groups
    }

    /// Copy a token into the shared group. Deliberately NEVER deletes first: this runs
    /// on every launch, and a delete followed by a failed add would destroy the only
    /// copy of the pairing token and silently force the user to pair again.
    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        guard !value.isEmpty else { return false }
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // Use the prefix expanded by Xcode for this signing identity, rather than
        // the original author's team. Keep the legacy TrollStore group as fallback.
        for group in accessGroups {
            var query = base
            query[kSecAttrAccessGroup as String] = group

            var update = query
            update[kSecValueData as String] = Data(value.utf8)
            // A share or a notification reply can arrive while the phone is locked, so
            // the token has to be readable after the first unlock.
            update[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let added = SecItemAdd(update as CFDictionary, nil)
            if added == errSecSuccess { return true }
            if added == errSecDuplicateItem {
                let attrs: [String: Any] = [
                    kSecValueData as String: Data(value.utf8),
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
                ]
                if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecSuccess { return true }
            }
        }
        return false
    }

    static func load(account: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        for group in accessGroups {
            query[kSecAttrAccessGroup as String] = group
            var out: AnyObject?
            if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
               let data = out as? Data {
                return String(data: data, encoding: .utf8)
            }
        }
        return nil
    }

    static func delete(account: String) {
        for group in accessGroups {
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecAttrAccessGroup as String: group,
            ] as CFDictionary)
        }
    }
}
