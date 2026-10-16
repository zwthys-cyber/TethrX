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
    private enum NetPath { case undecided, wifi, internet }
    private enum WStep { case host, serverAccess, grok, signin, node, run, choose, serverToken, page, scan }

    /// The ordered steps. How the bridge is started depends on the chosen network path.
    private var steps: [WStep] {
        if serverMode {
            return [.host, .serverAccess, .grok, .signin, .node, .run, .serverToken, .scan]
        }
        return [.host, .grok, .signin, .node, .choose, .run, .page, .scan]
    }
    private var current: WStep { steps[max(0, min(idx, steps.count - 1))] }
    private var firstTailIndex: Int { 5 }   // desktop index right after `choose`

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
            if args.contains("-serverPath") { serverMode = true; path = .internet }
            if args.contains("-netPath") { path = .internet }
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
                 ? LocalizedStringKey("Use an SSH app on this phone to set up your Linux server. The bridge gives the server a secure internet address, so the phone connects over Wi-Fi or cellular with no VPN. No personal computer is needed.")
                 : LocalizedStringKey("Choose a computer or a Linux server. Already running a bridge? Enter its address and pairing token to connect directly."))
                .font(Grok.sans(14)).foregroundStyle(Grok.textDim).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if current != .scan {
                Button("My bridge is already running") {
                    focus = nil
                    if serverMode { path = .internet }
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
                choice("Linux server", "Set up over SSH from your phone; connect from anywhere, no VPN") {
                    serverMode = true
                    path = .internet
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
                para("Install the bridge from this project's GitHub release. This includes the version required by the app even when npm's package-name release is older.")
                codeLine(AppState.bridgeInstallCommand)
                if serverMode {
                    para("Start the bridge with an internet tunnel. It prints a public https address and a pairing link for the next step.")
                    codeLine("tethrx-bridge --tunnel")
                    note("The first start downloads Cloudflare's tunnel program. No Cloudflare account, open port or VPN is needed. Keep this SSH session open while pairing. To keep the bridge running after disconnecting, follow the Linux service setup in the server guide.")
                    Link("Linux server setup guide", destination: URL(string: "https://github.com/zwthys-cyber/TethrX/blob/main/docs/linux-server.md")!)
                        .font(Grok.sans(14)).foregroundStyle(Grok.text)
                } else if path == .internet {
                    para("Start the installed bridge with an internet tunnel. It keeps running and gives your computer a secure public address. Leave it going.")
                    codeLine("tethrx-bridge --tunnel")
                    note("The first start downloads Cloudflare's tunnel program. No account, open port or VPN is needed. Every request still needs the pairing token.")
                } else {
                    para("Start the installed bridge. It prints a pairing token and keeps running. Leave it going.")
                    codeLine("GROK_REMOTE_HOST=0.0.0.0 tethrx-bridge")
                    note("Leave that window open. This listens beyond the computer itself so the phone can connect on a network you trust. The pairing token is what protects it.")
                }
                nav("The bridge is running")
            }
        case .choose:
            cardShell("How will your phone reach it?") {
                para("Pick how this phone connects to the bridge:")
                choice("Same Wi-Fi", "phone + computer on one network, simplest") { path = .wifi; idx = firstTailIndex }
                choice("From anywhere", "Wi-Fi or cellular, no VPN needed") { path = .internet; idx = firstTailIndex }
                if idx > 0 { backButton }
            }
        case .serverToken:
            cardShell("Copy the pairing link") {
                para("When the bridge is connected, the terminal shows an internet address and a pairing link starting with tethrx://pair. Copy the whole link. Opening it on this iPhone pairs the app, or you can paste it on the next screen.")
                note("If the bridge runs as a service, or the link has scrolled away, print it again in your private SSH terminal:")
                codeLine("tethrx-bridge pair")
                note("The link contains the pairing token. Do not share it or post it publicly. Do not open localhost:4180 on this iPhone.")
                nav("I copied the pairing link")
            }
        case .page:
            cardShell("On the computer, open this page") {
                para("Type this into the browser on the computer that is running the bridge. Do not open it on this phone. localhost means that computer, and the page refuses every other device.")
                codeLine("http://localhost:4180/pair")
                note("Type it in the address bar yourself. A tap, or pasting it into this phone, will not open it. When the QR codes are on the computer screen, continue. If the page says the phone cannot reach the bridge, the bridge was started without GROK_REMOTE_HOST=0.0.0.0.")
                nav("I see the QR codes")
            }
        case .scan:
            cardShell(serverMode ? "Connect to your server" : (path == .internet ? "Scan the Internet code" : "Scan the Wi-Fi code")) {
                if serverMode {
                    para("Paste the pairing link from the server terminal. It works over Wi-Fi or cellular, with no VPN.")
                    pasteLinkButton
                } else {
                    para(path == .internet
                         ? "On the pairing page, tap Scan to pair and aim at the code labelled INTERNET."
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

                HStack(spacing: 12) {
                    divider
                    Text("or enter by hand").font(Grok.sans(14)).foregroundStyle(Grok.textFaint).fixedSize()
                    divider
                }
                .padding(.vertical, 2)

                field(label: "Bridge address", placeholder: serverMode || path == .internet ? "https://….trycloudflare.com" : "192.168.1.10:4180", text: $app.baseURLString, secure: false)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($focus, equals: .address).submitLabel(.next).onSubmit { focus = .token }
                    .onChange(of: app.baseURLString) { _, text in
                        // A whole pairing link pasted into the address field: split it up.
                        if let link = PairingLink(text) { use(link, connect: false) }
                    }
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
        guard let link = PairingLink(s) else {
            app.errorMessage = String(loc: "That doesn't look like a TethrX pairing code.")
            return
        }
        use(link, connect: true)
    }

    /// Fill the fields from a pairing link. A link with a fingerprint pairs straight
    /// over pinned HTTPS, and keeps the plain address as the way back if that TLS
    /// port ever stops answering.
    private func use(_ link: PairingLink, connect: Bool) {
        focus = nil
        app.baseURLString = link.address
        app.pin = link.pin
        app.plainBase = link.plainBase
        app.token = link.token
        if connect { Task { await app.connect() } }
    }

    private var pasteLinkButton: some View {
        PasteButton(payloadType: String.self) { strings in
            guard let text = strings.first else { return }
            Task { @MainActor in
                if let link = PairingLink(text) {
                    use(link, connect: true)
                } else {
                    app.errorMessage = String(loc: "That doesn't look like a TethrX pairing link. Copy the whole line starting with tethrx://pair.")
                }
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonBorderShape(.capsule)
        .tint(Grok.accent)
    }
}

/// A monospaced command row with a copy button that flips to a checkmark on tap.
struct CopyableCode: View {
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
