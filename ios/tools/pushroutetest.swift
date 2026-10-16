// Checks PushRoute's provisioning-profile parsing on profiles shaped like the ones
// ESign re-signs with: a CMS envelope (binary junk) around an XML plist.
//
//   swiftc -O -o /tmp/pushroutetest ios/tools/pushroutetest.swift ios/GrokRemote/PushRoute.swift
//   /tmp/pushroutetest
//
// CI runs exactly that.
import Foundation

@main
enum PushRouteTest {
    static var failures = 0

    static func expect(_ condition: Bool, _ what: String) {
        print(condition ? "ok   \(what)" : "FAIL \(what)")
        if !condition { failures += 1 }
    }

    static func provision(_ entitlements: [String: Any], team: String = "ABCDE12345") -> Data {
        let plist: [String: Any] = ["Name": "ESign", "TeamIdentifier": [team], "Entitlements": entitlements]
        let xml = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return Data([0x30, 0x82, 0x3c, 0x3f, 0x00, 0xff]) + xml + Data([0x00, 0xa0, 0x82, 0x3c])
    }

    static func main() {
        let prod = PushRoute.parse(provision: provision(["aps-environment": "production"]))
        expect(prod == .init(environment: .production, teamId: "ABCDE12345"), "production profile")

        let dev = PushRoute.parse(provision: provision(["aps-environment": "development", "get-task-allow": true]))
        expect(dev?.environment == .development, "development profile uses the sandbox")

        let none = PushRoute.parse(provision: provision(["application-identifier": "ABCDE12345.nsk-164.v-team.cn"]))
        expect(none != nil && none?.environment == nil, "profile without push is reported as such")

        expect(PushRoute.parse(provision: Data("not a profile".utf8)) == nil, "garbage is rejected")

        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("push route: PASS")
    }
}
