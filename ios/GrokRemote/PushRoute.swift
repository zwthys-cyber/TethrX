import Foundation

/// Which APNs topic and environment this install's device token belongs to.
///
/// The App Store app is always `com.tethrx.app` on production. A re-signed build
/// (ESign and similar) has the bundle id of the signer's profile, and the profile's
/// `aps-environment` decides whether Apple issued the token for production or for
/// the sandbox; a token sent to the other host is rejected as BadDeviceToken.
enum PushRoute {
    enum Environment: String { case production, development }

    /// What the embedded provisioning profile allows. `nil` means the profile has no
    /// push entitlement at all (registration will fail); no profile means App Store.
    struct Profile: Equatable {
        var environment: Environment?
        var teamId: String?
    }

    static let topic = Bundle.main.bundleIdentifier ?? "com.tethrx.app"

    static let profile: Profile = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let parsed = parse(provision: data)
        else { return Profile(environment: .production, teamId: nil) }
        return parsed
    }()

    static var environment: Environment { profile.environment ?? .production }

    /// A `.mobileprovision` is a CMS envelope around a plain XML plist; the plist is
    /// stored unencrypted, so it can be cut out without a CMS decoder.
    static func parse(provision data: Data) -> Profile? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any]
        else { return nil }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        let aps = entitlements["aps-environment"] as? String
        let team = (plist["TeamIdentifier"] as? [String])?.first
            ?? entitlements["com.apple.developer.team-identifier"] as? String
        return Profile(environment: aps.flatMap(Environment.init(rawValue:)), teamId: team)
    }
}
