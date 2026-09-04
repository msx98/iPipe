import SwiftUI

@Observable
@MainActor
final class TrendingModel {
    var items: [StreamItem] = []
    var isLoading = false
    var error: String?
    private var loaded = false

    func load(app: AppModel, force: Bool = false) async {
        if isLoading { return }
        if loaded && !force { return }
        isLoading = true
        error = nil
        do {
            items = try await app.extraction.trending()
            loaded = true
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct TrendingView: View {
    @Environment(AppModel.self) private var app
    @State private var model = TrendingModel()
    @State private var showDownloads = false

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.trendingPath) {
            Group {
                if let error = model.error {
                    ErrorStateView(message: error) {
                        Task { await model.load(app: app, force: true) }
                    }
                } else if model.items.isEmpty && model.isLoading {
                    ProgressView("Loading trending…")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 18) {
                            ForEach(model.items) { stream in
                                StreamCell(stream: stream)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .refreshable { await model.load(app: app, force: true) }
                }
            }
            .navigationTitle("Trending")
            .toolbar { StandardToolbar() }
            .sheet(isPresented: $showDownloads) {
                NavigationStack {
                    DownloadsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") {
                                    showDownloads = false
                                }
                            }
                        }
                }
            }
            .task { await model.load(app: app) }
        }
    }
}
