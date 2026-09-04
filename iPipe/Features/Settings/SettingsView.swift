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
                    NavigationLink {
                        TabsEditorView(order: app.tabOrder, hidden: app.hiddenTabs)
                    } label: {
                        Label("Tabs", systemImage: "square.grid.2x2")
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

/// Edits a local snapshot of the tab layout and persists it on Done without
/// mutating the running app's `tabOrder`/`hiddenTabs` (changes apply next launch).
private struct TabsEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var order: [AppModel.RootTab]
    @State private var hidden: Set<AppModel.RootTab>

    init(order: [AppModel.RootTab], hidden: Set<AppModel.RootTab>) {
        _order = State(initialValue: order)
        _hidden = State(initialValue: hidden)
    }

    var body: some View {
        List {
            Section {
                ForEach(order, id: \.self) { tab in
                    Toggle(isOn: binding(for: tab)) {
                        Label(name(for: tab), systemImage: icon(for: tab))
                    }
                    .disabled(tab == .settings)
                }
                .onMove { order.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Tabs")
            } footer: {
                Text("Restart the app to see changes.")
            }
        }
        .navigationTitle("Tabs")
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    app.saveTabConfiguration(order: order, hidden: hidden)
                    dismiss()
                }
            }
        }
    }

    private func binding(for tab: AppModel.RootTab) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(tab) },
            set: { isOn in
                if isOn {
                    hidden.remove(tab)
                } else {
                    hidden.insert(tab)
                }
            }
        )
    }

    private func name(for tab: AppModel.RootTab) -> String {
        switch tab {
        case .trending: return "Trending"
        case .search: return "Search"
        case .subscriptions: return "Subscriptions"
        case .playlists: return "Playlists"
        case .settings: return "Settings"
        }
    }

    private func icon(for tab: AppModel.RootTab) -> String {
        switch tab {
        case .trending: return "flame.fill"
        case .search: return "magnifyingglass"
        case .subscriptions: return "person.2.fill"
        case .playlists: return "list.bullet"
        case .settings: return "gearshape.fill"
        }
    }
}
