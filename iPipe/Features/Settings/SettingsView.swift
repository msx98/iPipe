import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    @State private var showLogin = false
    @State private var showImporter = false
    @State private var shareURL: URL?
    @State private var importFailed = false
    @State private var showLicense = false
    @State private var showClearHistoryConfirm = false

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.settingsPath) {
            Form {
                Section("Content source") {
                    Picker("Backend", selection: Binding(
                        get: { app.backend },
                        set: { app.setBackend($0) }
                    )) {
                        ForEach(AppModel.Backend.allCases) { backend in
                            Text(backend.rawValue).tag(backend)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Appearance") {
                    Picker("Theme", selection: Binding(
                        get: { app.colorSchemeChoice },
                        set: { app.setColorScheme($0) }
                    )) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                }
                Section("Data") {
                    Button("Clear watch history", role: .destructive) {
                        showClearHistoryConfirm = true
                    }
                    .disabled(app.history.isEmpty)
                }
                Section("Account") {
                    if app.signedIn {
                        Label("Signed in to YouTube", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button("Export cookies (.txt)") {
                            let text = CookieStore.shared.netscapeExport()
                            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cookies.txt")
                            if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
                                shareURL = url
                            }
                        }
                        Button("Sign out", role: .destructive) {
                            CookieStore.shared.signOut()
                            app.refreshSignedIn()
                        }
                    } else {
                        Button {
                            showLogin = true
                        } label: {
                            Label("Sign in to YouTube", systemImage: "person.crop.circle")
                        }
                    }
                    Button("Import cookies…") {
                        showImporter = true
                    }
                }
                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                    Button {
                        showLicense = true
                    } label: {
                        HStack {
                            Text("License")
                            Spacer()
                            Text("GPL v3").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { StandardToolbar() }
            .sheet(isPresented: $showLogin) {
                YouTubeLoginView {
                    app.refreshSignedIn()
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { shareURL != nil },
                    set: { if !$0 { shareURL = nil } }
                )
            ) {
                if let shareURL {
                    ShareSheet(items: [shareURL])
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.plainText, .json, .data],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    importCookies(from: url)
                }
            }
            .sheet(isPresented: $showLicense) {
                LicenseTextView.gplv3
            }
            .alert("Import failed", isPresented: $importFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Could not parse the selected cookies file (Netscape .txt or JSON expected).")
            }
            .modifier(ClearHistoryConfirmation(isPresented: $showClearHistoryConfirm, onClear: app.clearHistory))
        }
    }

    private func importCookies(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let text = try? String(contentsOf: url, encoding: .utf8),
           CookieStore.shared.importText(text) {
            app.refreshSignedIn()
        } else {
            importFailed = true
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
