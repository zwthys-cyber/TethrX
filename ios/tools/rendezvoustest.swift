// Checks Rendezvous.swift and PairingLink against announcements and links made by
// the bridge's own code (bridge/test/rendezvous-fixture.mjs). The two sides sign
// and verify the same bytes, so a drift in either one fails here, not on a phone
// that silently stops following its server's new address.
//
//   node bridge/test/rendezvous-fixture.mjs /tmp/rendezvous.json
//   swiftc -O -o /tmp/rendezvoustest ios/tools/rendezvoustest.swift ios/GrokRemote/Rendezvous.swift
//   /tmp/rendezvoustest /tmp/rendezvous.json
//
// CI runs exactly that.
import Foundation

@main
enum RendezvousTest {
    static var failures = 0

    static func expect(_ condition: Bool, _ what: String) {
        print(condition ? "ok   \(what)" : "FAIL \(what)")
        if !condition { failures += 1 }
    }

    static func main() {
        guard CommandLine.arguments.count > 1,
              let data = FileManager.default.contents(atPath: CommandLine.arguments[1]),
              let fx = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            print("usage: rendezvoustest <fixture.json>")
            exit(2)
        }
        let token = fx["token"]!, serverId = fx["serverId"]!, body = fx["body"]!

        expect(Rendezvous.topic(token: token) == fx["topic"], "topic matches the bridge's")

        let best = Rendezvous.latest(token: token, body: body, serverId: serverId)
        expect(best?.url == fx["expectUrl"], "newest signed address wins (got \(best?.url ?? "nil"))")
        expect(Rendezvous.latest(token: token + "x", body: body, serverId: serverId) == nil,
               "nothing verifies under a different token")
        expect(Rendezvous.latest(token: token, body: body, serverId: nil)?.url == "https://other-bridge.trycloudflare.com",
               "without a known serverId the newest signed https record is used")

        let link = PairingLink(fx["pairingLink"]!)
        expect(link?.address == "https://newest.trycloudflare.com", "pairing link address")
        expect(link?.token == "tok/+=&x", "pairing link token survives percent-encoding")
        expect(link?.pin == "" && link?.plainBase == "", "an internet link is not pinned")

        let pinned = PairingLink("tethrx://pair?addr=192.168.1.5%3A4180&token=abc&tls=4181&fp=deadbeef")
        expect(pinned?.address == "https://192.168.1.5:4181", "LAN QR upgrades to pinned https")
        expect(pinned?.pin == "deadbeef" && pinned?.plainBase == "http://192.168.1.5:4180", "pinned QR keeps its way back")
        expect(PairingLink("https://example.com") == nil, "a plain URL is not a pairing link")
        expect(PairingLink("tethrx://pair?addr=x") == nil, "a link without a token is rejected")

        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
        print("all rendezvous checks passed")
    }
}
