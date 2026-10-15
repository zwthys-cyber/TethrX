import SwiftUI
import UIKit

/// Connect either a desktop computer or a headless Linux server. The server
/// path uses SSH, device-code login and manual pairing, with no desktop browser.
struct PairingView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var discovery = BridgeDiscovery()
    @FocusState private var focus: Field?
    @State private var showScanner = false
    @State private var idx = 0
    @State private var path: NetPath = .undecided
    @State private var serverMode = false

    private enum Field { case address, token }
    private enum NetPath { case undecided, wifi, tailscale }
    private enum WStep { case host, serverAccess, grok, signin, node, run, choose, tsMac, tsServer, tsPhone, serverToken, page, scan }

    /// The ordered steps — the tail depends on the chosen network path.
    private var steps: [WStep] {
        if serverMode {
            return [.host, .serverAccess, .grok, .signin, .node, .tsServer, .tsPhone, .run, .serverToken, .scan]
        }
        let base: [WStep] = [.host, .grok, .signin, .node, .run, .choose]
        let tail: [WStep] = path == .tailscale ? [.tsMac, .tsPhone, .page, .scan] : [.page, .scan]
        return base + tail
    }
    private var current: WStep { steps[max(0, min(idx, steps.count - 1))] }
    private var firstTailIndex: Int { 6 }   // desktop index right after `choose`

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                card
                if let err = app.errorMessage { errorRow(err) }
                footer
            }
            .padding(.horizontal, Grok.gutter).padding(.vertical, 24)
            .padding(.top, 8)
            .animation(.easeInOut(duration: 0.22), value: idx)
            .animation(.easeInOut(duration: 0.22), value: path)
        }
        .background(Grok.bg)
        .navigationTitle("Connect a computer or server")
        .navigationBarTitleDisplayMode(.inline)
        .grokBar()
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showScanner) {
            ScanSheet { code in showScanner = false; handleScanned(code) }
        }
        .onAppear {
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-serverPath") { serverMode = true; path = .tailscale }
            if args.contains("-tsPath") { path = .tailscale }
            if let i = args.firstIndex(of: "-startStep"), i + 1 < args.count, let n = Int(args[i + 1]) {
                idx = max(0, min(n, steps.count - 1))
            }
            #endif
            // Returning users can skip setup with the direct-connect shortcut.
        }
        .onChange(of: current) { _, step in
            // Browse only on the scan step, where an address is actually wanted.
            if step == .scan, !serverMode, path == .wifi { discovery.start() } else { discovery.stop() }
        }
        .onDisappear { discovery.stop() }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(serverMode
                 ? LocalizedStringKey("Use an SSH app on this phone to set up your Linux server. Tailscale connects the phone to it over Wi-Fi or cellular. No personal computer is needed.")
                 : LocalizedStringKey("Choose a computer or a Linux server. Already running a bridge? Enter its address and pairing token to connect directly."))
                .font(Grok.sans(14)).foregroundStyle(Grok.textDim).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if current != .scan {
                Button("My bridge is already running") {
                    focus = nil
                    if serverMode { path = .tailscale }
                    idx = steps.count - 1
                }
                .font(Grok.sans(14)).foregroundStyle(Grok.textDim)
                .frame(minHeight: 44)
            }
            HStack(spacing: 5) {
                ForEach(0..<steps.count, id: \.self) { i in
                    Capsule().fill(i <= idx ? Grok.accent : Grok.hairlineStrong)
                        .frame(height: 3).frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: Steps

    @ViewBuilder private var card: some View {
        switch current {
        case .host:
            cardShell("Where will Grok run?") {
                choice("Linux server", "Set up over SSH from your phone; connect over cellular with Tailscale") {
                    serverMode = true
                    path = .tailscale
                    idx = 1
                }
                choice("Personal computer", "Mac or another computer with a browser") {
                    serverMode = false
                    path = .undecided
                    idx = 1
                }
            }
        case .serverAccess:
            cardShell("Open your server's SSH terminal") {
                para("Use your hosting provider's web terminal or an SSH app on this iPhone. Run the following setup commands on the Linux server, not on the phone itself.")
                note("Use the same Linux account for Grok Build and the bridge, so they share the same sign-in and files.")
                nav("The server terminal is open")
            }
        case .grok:
            cardShell(serverMode ? "Set up Grok Build on your server" : "Set up Grok Build on your computer") {
                para(serverMode
                     ? "Install Grok Build in the server's SSH terminal. Your code and tasks will run on that server."
                     : "TethrX drives Grok Build, xAI's terminal coding agent, on a computer you own. Install it there with one command:")
                codeLine("curl -fsSL https://x.ai/cli/install.sh | bash")
                note("Already installed? Check with  grok --version  and skip ahead.")
                nav("Grok Build is installed")
            }
        case .signin:
            cardShell("Sign in to Grok") {
                if serverMode {
                    para("Use device-code sign-in on the server. Open the URL it prints in Safari on this iPhone, enter the code and finish signing in.")
                    codeLine("grok login --device-auth")
                    note("The server does not need a browser. Keep its terminal open until sign-in finishes.")
                } else {
                    para("Run Grok once on your computer. It opens your browser to sign in with your xAI account, then remembers you.")
                    codeLine("grok")
                    note("Sign-in trouble? Some privacy browsers (Brave, and others with strict shields) block the localhost redirect the login uses. Set Safari or Chrome as your default browser, run  grok login  to retry, then switch back. You're set when  grok --version  prints a version without complaints.")
                }
                nav("I'm signed in")
            }
        case .node:
            cardShell("Install Node.js") {
                para(serverMode
                     ? "Install Node.js 20 or newer on the Linux server using the Linux instructions at nodejs.org. Check the version in the same SSH terminal."
                     : "The bridge runs on Node.js 20 or newer. Install it from nodejs.org if you don't already have it.")
                codeLine("node --version")
                note("Should print v20 or higher.")
                nav("Node is installed")
            }
        case .run:
            cardShell("Start the bridge") {
                if serverMode {
                    para("Start the bridge on the server's Tailscale address. Copy the pairing token printed in this terminal for the next step.")
                    codeLine("GROK_REMOTE_HOST=\"$(tailscale ip -4)\" npx tethrx-bridge")
                    note("Keep this SSH session open while pairing. To keep the bridge running after disconnecting, follow the Linux service setup in the server guide.")
                    Link("Linux server setup guide", destination: URL(string: "https://github.com/zwthys-cyber/TethrX/blob/main/docs/linux-server.md")!)
                        .font(Grok.sans(14)).foregroundStyle(Grok.text)
                } else {
                    para("One command downloads and starts the bridge on your computer. It prints a pairing token and keeps running. Leave it going.")
                    codeLine("GROK_REMOTE_HOST=0.0.0.0 npx tethrx-bridge")
                    note("Leave that window open. This listens beyond the computer itself so the phone can connect on a network you trust. The pairing token is what protects it.")
                }
                nav("The bridge is running")
            }
        case .choose:
            cardShell("How will your phone reach it?") {
                para("Pick how this phone connects to the bridge:")
                choice("Same Wi-Fi", "phone + computer on one network, simplest") { path = .wifi; idx = firstTailIndex }
                choice("From anywhere", "works on cellular too, via Tailscale") { path = .tailscale; idx = firstTailIndex }
                if idx > 0 { backButton }
            }
        case .tsMac:
            cardShell("Install Tailscale on your computer") {
                para("Tailscale is a free private network that links this phone to your computer from anywhere. Install it on your computer, then sign in to create a free account. You can use Google, Apple, GitHub, or email.")
                note("Get it from the Mac App Store or tailscale.com/download. Once you're signed in, a menu-bar icon shows it's connected.")
                choice("I use a Linux server", "Use SSH setup instead of a desktop app") {
                    serverMode = true
                    path = .tailscale
                    idx = 1
                }
                nav("Installed and signed in")
            }
        case .tsServer:
            cardShell("Install Tailscale on the server") {
                para("Run these commands in the Linux server's terminal. Open the sign-in URL it prints in Safari on this iPhone and authorize the server.")
                codeLine("curl -fsSL https://tailscale.com/install.sh | sh")
                codeLine("sudo tailscale up")
                codeLine("tailscale ip -4")
                note("Save the 100.x.y.z address. The bridge will listen only on this private network; no public port forwarding is needed.")
                nav("The server is connected to Tailscale")
            }
        case .tsPhone:
            cardShell("Install Tailscale on this phone") {
                para(serverMode
                     ? "Install Tailscale from the App Store on this iPhone. Sign in to the same Tailscale network as the server and enable the VPN connection."
                     : "Now install Tailscale from the App Store on this phone and sign in with the same account you just used on your computer. Using the same account on both is what links the two devices.")
                note(serverMode
                     ? "Keep Tailscale connected on this phone when using Wi-Fi or cellular. Check that the server is online in its device list."
                     : "Open the Tailscale app and check that both your computer and this phone show up in the list and appear connected.")
                nav("Signed in with the same account")
            }
        case .serverToken:
            cardShell("Copy the server address and pairing token") {
                para("Use the server's Tailscale IPv4 address with port 4180, and the pairing token printed when the bridge started. Enter both on the next screen.")
                codeLine("http://100.x.y.z:4180")
                note("If the bridge runs as a service, read its token from the server account's configuration in your private SSH terminal:")
                codeLine("node -p 'JSON.parse(require(\"fs\").readFileSync(require(\"os\").homedir()+\"/.grok-remote/config.json\",\"utf8\")).token'")
                note("No QR code or server browser is required. Do not open localhost:4180 on this iPhone or share the pairing token.")
                nav("I have the server address and token")
            }
        case .page:
            cardShell("On the computer, open this page") {
                para("Type this into the browser on the computer that is running the bridge. Do not open it on this phone. localhost means that computer, and the page refuses every other device.")
                codeLine("http://localhost:4180/pair")
                note("Type it in the address bar yourself. A tap, or pasting it into this phone, will not open it. When the QR codes are on the computer screen, continue. If the page says the phone cannot reach the bridge, the bridge was started without GROK_REMOTE_HOST=0.0.0.0.")
                nav("I see the QR codes")
            }
        case .scan:
            cardShell(serverMode ? "Connect to your server" : (path == .tailscale ? "Scan the Tailscale code" : "Scan the Wi-Fi code")) {
                if serverMode {
                    para("Paste the server's Tailscale address and pairing token below. Keep Tailscale connected on this iPhone, including when using cellular.")
                } else {
                    para(path == .tailscale
                         ? "On the pairing page, tap Scan to pair and aim at the code labelled TAILSCALE."
                         : "On the pairing page, tap Scan to pair and aim at the code labelled WI-FI / LAN.")
                    Button { focus = nil; showScanner = true } label: {
                        Label("Scan to pair", systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(PillButton(kind: .prominent))
                }

                // Bridges advertising themselves on this network — tap to fill the
                // address, then only the token is left to enter.
                if !serverMode, path == .wifi, !discovery.found.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ListSectionLabel("Found nearby")
                        ForEach(discovery.found) { bridge in
                            Button {
                                Haptics.tap()
                                app.baseURLString = bridge.address
                                focus = .token
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "desktopcomputer").font(.system(size: 13)).foregroundStyle(Grok.textDim)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(bridge.name).font(Grok.sans(15)).foregroundStyle(Grok.text).lineLimit(1)
                                        Text(bridge.address).font(Grok.sans(13)).foregroundStyle(Grok.textFaint)
                                    }
                                    Spacer(minLength: 0)
                                    if app.baseURLString == bridge.address {
                                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Grok.accent)
                                    }
                                }
                                .padding(12)
                                .background(Grok.raised)
                                .overlay(RoundedRectangle(cornerRadius: Grok.R.small, style: .continuous).stroke(Grok.hairline, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: Grok.R.small, style: .continuous))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if !serverMode {
                    HStack(spacing: 12) {
                        divider
                        Text("or enter by hand").font(Grok.sans(14)).foregroundStyle(Grok.textFaint).fixedSize()
                        divider
                    }
                    .padding(.vertical, 2)
                }

                field(label: "Bridge address", placeholder: path == .tailscale ? "100.x.y.z:4180" : "192.168.1.10:4180", text: $app.baseURLString, secure: false)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .address).submitLabel(.next).onSubmit { focus = .token }
                field(label: "Pairing token", placeholder: serverMode ? "from the server terminal" : "from the pairing page", text: $app.token, secure: true)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .token).submitLabel(.go).onSubmit { focus = nil; Task { await app.connect() } }

                Button { focus = nil; Task { await app.connect() } } label: {
                    HStack(spacing: 10) {
                        if app.connecting { ProgressView().controlSize(.small).tint(.white) }
                        (app.connecting ? Text("Connecting…") : Text("Connect"))
                    }
                }
                .buttonStyle(PillButton(kind: .prominent))
                .disabled(app.connecting || app.baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || app.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                backButton
            }
        }
    }

    // MARK: Card shell + pieces

    private func cardShell<C: View>(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ListSectionLabel("Step \(idx + 1) / \(steps.count)")
            Text(title).font(Grok.sans(23, .semibold)).latinTracking(-0.4)
                .foregroundStyle(Grok.text).fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(Grok.pad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Grok.raised)
        .overlay(RoundedRectangle(cornerRadius: Grok.R.card, style: .continuous).stroke(Grok.hairlineStrong, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Grok.R.card, style: .continuous))
    }

    private func para(_ s: LocalizedStringKey) -> some View {
        Text(s).font(Grok.sans(15)).foregroundStyle(Grok.textDim).lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func note(_ s: LocalizedStringKey) -> some View {
        Text(s).font(Grok.sans(14)).foregroundStyle(Grok.textFaint).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
    private func codeLine(_ s: String) -> some View { CopyableCode(text: s) }
    private var divider: some View { Rectangle().fill(Grok.hairline).frame(height: 1) }

    private func choice(_ title: LocalizedStringKey, _ sub: LocalizedStringKey, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Grok.sans(16, .semibold)).foregroundStyle(Grok.text)
                    Text(sub).font(Grok.sans(14)).foregroundStyle(Grok.textDim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Grok.textFaint)
            }
            .padding(Grok.pad)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Grok.R.small, style: .continuous).stroke(Grok.hairlineStrong, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Grok.R.small, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Advance control: a "completed" pill, plus a back link when not on step 1.
    @ViewBuilder private func nav(_ label: LocalizedStringKey) -> some View {
        Button { focus = nil; Haptics.tap(.medium); idx = min(idx + 1, steps.count - 1) } label: {
            HStack(spacing: 8) { Text(label); Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
        }
        .buttonStyle(PillButton(kind: .prominent))
        if idx > 0 { backButton }
    }
    private var backButton: some View {
        Button { path = !serverMode && idx == firstTailIndex ? .undecided : path; idx = max(idx - 1, 0) } label: {
            Label("back", systemImage: "chevron.left").font(Grok.sans(15))
                // A bare label is one line of 15pt type tall, well under the 44pt
                // a finger needs; the height lives in the label so the whole width
                // of the card is the target.
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(Grok.textFaint)
    }

    private func errorRow(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("!").font(Grok.sans(15, .bold)).foregroundStyle(Grok.danger)
            Text(err).font(Grok.sans(15)).foregroundStyle(Grok.danger).lineSpacing(2)
        }
    }
    private var footer: some View {
        Text("A client for Grok Build · independent, not affiliated with xAI")
            .font(Grok.sans(13)).foregroundStyle(Grok.textFaint)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func field(label: LocalizedStringKey, placeholder: LocalizedStringKey, text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ListSectionLabel(label)
            FieldBox {
                Group {
                    if secure {
                        SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Grok.textFaint))
                    } else {
                        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Grok.textFaint))
                    }
                }
                .font(Grok.sans(17))
                .foregroundStyle(Grok.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Parse a scanned `tethrx://pair?addr=…&token=…[&tls=…&fp=…]` code, fill the
    /// fields, and connect. When the code carries the bridge's cert fingerprint,
    /// pair straight over pinned HTTPS — the QR is the out-of-band trust channel.
    private func handleScanned(_ s: String) {
        guard let c = URLComponents(string: s), c.scheme == "tethrx", c.host == "pair",
              let addr = c.queryItems?.first(where: { $0.name == "addr" })?.value,
              let tok = c.queryItems?.first(where: { $0.name == "token" })?.value,
              !addr.isEmpty, !tok.isEmpty else {
            app.errorMessage = String(loc: "That doesn't look like a TethrX pairing code.")
            return
        }
        let fp = c.queryItems?.first(where: { $0.name == "fp" })?.value ?? ""
        let tlsPort = c.queryItems?.first(where: { $0.name == "tls" })?.value ?? ""
        // URLComponents, not split(":") — an addr carrying a scheme would yield
        // host "http" and build "https://http:8443".
        let plainURL = addr.contains("://") ? addr : "http://\(addr)"
        if !fp.isEmpty, !tlsPort.isEmpty, let host = URLComponents(string: plainURL)?.host {
            app.baseURLString = "https://\(host):\(tlsPort)"
            app.pin = fp
            // The QR's plain address is the way back if that TLS port ever stops
            // answering — without it a dead pin means re-running this whole wizard.
            app.plainBase = plainURL
        } else {
            app.baseURLString = addr
            app.pin = ""
            app.plainBase = ""
        }
        app.token = tok
        Task { await app.connect() }
    }
}

/// A monospaced command row with a copy button that flips to a checkmark on tap.
private struct CopyableCode: View {
    let text: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(Grok.mono(14)).foregroundStyle(Grok.text)
                .lineLimit(2).minimumScaleFactor(0.7).textSelection(.enabled)
            Spacer(minLength: 0)
            Button {
                UIPasteboard.general.string = text
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
                    withAnimation(.easeIn(duration: 0.2)) { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(copied ? Grok.accent : Grok.textDim)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Text(copied ? "Copied" : "Copy"))
        }
        .padding(.horizontal, Grok.pad).padding(.vertical, 12)
        .background(Grok.bg)
        .overlay(RoundedRectangle(cornerRadius: Grok.R.small, style: .continuous).stroke(Grok.hairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Grok.R.small, style: .continuous))
    }
}
