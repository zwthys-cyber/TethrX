import SwiftUI

/// Pair an additional computer from Settings — no need to disconnect from the one
/// you're already on. If the new credentials don't connect, AppState puts the
/// previous computer back, so a failed attempt can't strand you.
struct AddComputerSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var discovery = BridgeDiscovery()

    @State private var address = ""
    @State private var pairingToken = ""
    @State private var showScanner = false
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("On a computer with a browser, open this address to show a pairing QR code. For a Linux server, use the address and token fields below instead.")
                        .font(Grok.sans(15)).foregroundStyle(Grok.textDim).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    codeLine("http://localhost:4180/pair")
                    Text("Using a Linux server? No browser, QR code or VPN is needed. Start the bridge with  tethrx-bridge --tunnel, run  tethrx-bridge pair, and paste the pairing link it prints.")
                        .font(Grok.sans(14)).foregroundStyle(Grok.textDim).lineSpacing(3)
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        Task { @MainActor in
                            if let link = PairingLink(text) {
                                use(link)
                            } else {
                                failure = String(loc: "That doesn't look like a TethrX pairing link. Copy the whole line starting with tethrx://pair.")
                            }
                        }
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonBorderShape(.capsule)
                    .tint(Grok.accent)
                    Link("Linux server setup guide", destination: URL(string: "https://github.com/zwthys-cyber/TethrX/blob/main/docs/linux-server.md")!)
                        .font(Grok.sans(14)).foregroundStyle(Grok.text)

                    Button { showScanner = true } label: {
                        Label("Scan to pair", systemImage: "qrcode.viewfinder")
                    }
                    .buttonStyle(PillButton(kind: .prominent))

                    if !discovery.found.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ListSectionLabel("Nearby")
                            ForEach(discovery.found) { bridge in
                                Button {
                                    Haptics.tap()
                                    address = bridge.address
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "desktopcomputer").font(.system(size: 13)).foregroundStyle(Grok.textDim)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(bridge.name).font(Grok.sans(15)).foregroundStyle(Grok.text).lineLimit(1)
                                            Text(bridge.address).font(Grok.sans(13)).foregroundStyle(Grok.textFaint)
                                        }
                                        Spacer(minLength: 0)
                                        if address == bridge.address {
                                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Grok.accent)
                                        }
                                    }
                                    .padding(.horizontal, 12).padding(.vertical, 10)
                                    .background(Grok.raised)
                                    .overlay(RoundedRectangle(cornerRadius: Grok.R.small, style: .continuous).stroke(Grok.hairline, lineWidth: 1))
                                    .clipShape(RoundedRectangle(cornerRadius: Grok.R.small, style: .continuous))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            Text("Found on your network. Tap to fill the address, then enter that computer's token.")
                                .font(Grok.sans(13)).foregroundStyle(Grok.textFaint)
                        }
                    }

                    HStack(spacing: 12) {
                        divider
                        Text("or enter by hand").font(Grok.sans(14)).foregroundStyle(Grok.textFaint).fixedSize()
                        divider
                    }

                    field("Bridge address", "https://….trycloudflare.com", $address, secure: false)
                        .onChange(of: address) { _, text in
                            // A whole pairing link pasted into the address field: split it up.
                            if let link = PairingLink(text) {
                                address = link.address
                                pairingToken = link.token
                                scannedPin = link.pin
                                scannedPlain = link.plainBase
                            }
                        }
                    field("Pairing token", "from the server terminal or pairing page", $pairingToken, secure: true)

                    if let failure {
                        HStack(alignment: .top, spacing: 8) {
                            Text("!").font(Grok.sans(15, .bold)).foregroundStyle(Grok.danger)
                            Text(failure).font(Grok.sans(15)).foregroundStyle(Grok.danger).lineSpacing(2)
                        }
                    }

                    Button { Task { await add() } } label: {
                        HStack(spacing: 10) {
                            if working { ProgressView().controlSize(.small).tint(.white) }
                            (working ? Text("Connecting…") : Text("Add computer or server"))
                        }
                    }
                    .buttonStyle(PillButton(kind: .prominent))
                    .disabled(working || address.trimmingCharacters(in: .whitespaces).isEmpty
                              || pairingToken.trimmingCharacters(in: .whitespaces).isEmpty)

                    Text("Adding a computer or server switches to it. Your other connections stay paired, and you can switch between them any time.")
                        .font(Grok.sans(13)).foregroundStyle(Grok.textFaint).lineSpacing(3)
                }
                .padding(.horizontal, Grok.gutter).padding(.vertical, 20)
            }
            .background(Grok.bg)
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add computer or server")
            .navigationBarTitleDisplayMode(.inline)
            .grokBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Grok.textDim)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showScanner) {
            ScanSheet { code in showScanner = false; handleScanned(code) }
        }
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
    }

    private var divider: some View { Rectangle().fill(Grok.hairline).frame(height: 1) }

    @State private var scannedPin = ""   // cert fingerprint from the QR, if present
    @State private var scannedPlain = "" // and the plain address it was upgraded from

    private func add() async {
        working = true
        failure = nil
        defer { working = false }
        let ok = await app.addComputer(address: address.trimmingCharacters(in: .whitespaces),
                                       pairingToken: pairingToken.trimmingCharacters(in: .whitespaces),
                                       pin: scannedPin, plainBase: scannedPlain)
        if ok {
            Haptics.success()
            dismiss()
        } else {
            failure = app.errorMessage ?? String(loc: "Couldn't reach that computer. Check the address and that its bridge is running.")
        }
    }

    private func handleScanned(_ code: String) {
        guard let link = PairingLink(code) else {
            failure = String(loc: "That doesn't look like a TethrX pairing code.")
            return
        }
        use(link)
    }

    private func use(_ link: PairingLink) {
        address = link.address
        pairingToken = link.token
        scannedPin = link.pin
        scannedPlain = link.plainBase
        Task { await add() }
    }

    private func codeLine(_ s: String) -> some View {
        Text(s).font(Grok.sans(16)).foregroundStyle(Grok.text)
            .lineLimit(1).minimumScaleFactor(0.6).textSelection(.enabled)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Grok.raised)
            .overlay(RoundedRectangle(cornerRadius: Grok.R.small, style: .continuous).stroke(Grok.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: Grok.R.small, style: .continuous))
    }

    private func field(_ label: LocalizedStringKey, _ placeholder: LocalizedStringKey, _ text: Binding<String>, secure: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            ListSectionLabel(label)
            FieldBox {
                Group {
                    if secure {
                        SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Grok.textFaint))
                    } else {
                        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Grok.textFaint))
                            .keyboardType(.URL)
                    }
                }
                .font(Grok.sans(17))
                .foregroundStyle(Grok.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
