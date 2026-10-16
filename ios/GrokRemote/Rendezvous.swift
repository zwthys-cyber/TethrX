import Foundation
import CryptoKit

/// Finds a bridge's current internet address after its tunnel restarted.
///
/// A Cloudflare quick-tunnel address changes whenever the tunnel restarts, so the
/// bridge announces each new one on an ntfy topic. The topic name and the HMAC on
/// every announcement are derived from the pairing token (see bridge/src/tunnel.mjs),
/// so only the paired phone can find the topic, and an announcement nobody with the
/// token signed is ignored rather than followed — following one would send the
/// token to whoever posted it.
///
/// Foundation + CryptoKit only, so ios/tools/rendezvoustest.swift can check it on its own.
enum Rendezvous {
    static let defaultServer = "https://ntfy.sh"

    struct Record: Equatable {
        let url: String
        let serverId: String
        let ts: Int64
    }

    static func topic(token: String) -> String {
        let digest = SHA256.hash(data: Data(("tethrx-rendezvous-topic\n" + token).utf8))
        return "tethrx-" + String(hex(digest).prefix(40))
    }

    static func signature(token: String, url: String, serverId: String, ts: Int64) -> String {
        let key = SymmetricKey(data: Data(token.utf8))
        let message = Data("tethrx-rendezvous-v1\n\(url)\n\(serverId)\n\(ts)".utf8)
        return hex(HMAC<SHA256>.authenticationCode(for: message, using: key))
    }

    /// The newest correctly signed https address in an ntfy `/json?poll=1` body.
    static func latest(token: String, body: String, serverId: String?) -> Record? {
        var best: Record?
        for line in body.split(whereSeparator: \.isNewline) {
            guard let outer = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  outer["event"] as? String == "message",
                  let inner = outer["message"] as? String,
                  let rec = try? JSONSerialization.jsonObject(with: Data(inner.utf8)) as? [String: Any],
                  (rec["v"] as? NSNumber)?.intValue == 1,
                  let url = rec["url"] as? String, url.lowercased().hasPrefix("https://"),
                  let sid = rec["serverId"] as? String,
                  let ts = (rec["ts"] as? NSNumber)?.int64Value,
                  let sig = rec["sig"] as? String
            else { continue }
            if let serverId, !serverId.isEmpty, sid != serverId { continue }
            guard sig.lowercased() == signature(token: token, url: url, serverId: sid, ts: ts) else { continue }
            if best == nil || ts > best!.ts { best = Record(url: url, serverId: sid, ts: ts) }
        }
        return best
    }

    /// Ask the rendezvous server where this bridge is now. nil when nothing signed is there.
    static func lookup(server: String, token: String, serverId: String?) async -> Record? {
        var base = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty, !token.isEmpty,
              let url = URL(string: "\(base)/\(topic(token: token))/json?poll=1&since=12h") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        guard let reply = try? await URLSession.shared.data(for: req),
              (reply.1 as? HTTPURLResponse)?.statusCode == 200,
              let body = String(data: reply.0, encoding: .utf8) else { return nil }
        return latest(token: token, body: body, serverId: serverId)
    }

    private static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// A `tethrx://pair?addr=…&token=…[&tls=…&fp=…]` link: what the pairing QR code,
/// `tethrx-bridge pair` and the tunnel banner hand to the phone.
struct PairingLink: Equatable {
    /// The address to connect to (pinned https when the link carries a fingerprint).
    var address: String
    var token: String
    var pin: String = ""
    /// The plain-HTTP address to fall back to if a pinned port stops answering.
    var plainBase: String = ""

    init?(_ text: String) {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: s), c.scheme?.lowercased() == "tethrx", c.host?.lowercased() == "pair",
              let addr = c.queryItems?.first(where: { $0.name == "addr" })?.value,
              let tok = c.queryItems?.first(where: { $0.name == "token" })?.value,
              !addr.isEmpty, !tok.isEmpty else { return nil }
        let fp = c.queryItems?.first(where: { $0.name == "fp" })?.value ?? ""
        let tlsPort = c.queryItems?.first(where: { $0.name == "tls" })?.value ?? ""
        token = tok
        // URLComponents, not split(":") — an addr carrying a scheme would yield
        // host "http" and build "https://http:8443".
        let plainURL = addr.contains("://") ? addr : "http://\(addr)"
        if !fp.isEmpty, !tlsPort.isEmpty, plainURL.lowercased().hasPrefix("http://"),
           let host = URLComponents(string: plainURL)?.host {
            address = "https://\(host):\(tlsPort)"
            pin = fp
            plainBase = plainURL
        } else {
            address = addr
        }
    }

    /// The host to show when asking the user to confirm a link opened from elsewhere.
    var displayHost: String {
        URLComponents(string: address.contains("://") ? address : "http://\(address)")?.host ?? address
    }
}
