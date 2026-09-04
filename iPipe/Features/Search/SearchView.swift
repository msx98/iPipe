import SwiftUI

@Observable
@MainActor
final class SearchModel {
    var query = ""
    var filter: SearchFilter = .all
    var results: SearchResultKind?
    var isSearching = false
    var error: String?
    var suggestions: [String] = []
    var hasSearched = false

    func runSearch(app: AppModel) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        error = nil
        suggestions = []
        do {
            results = try await app.extraction.search(q, filter: filter)
            hasSearched = true
        } catch {
            self.error = error.localizedDescription
        }
        isSearching = false
    }

    func updateSuggestions(app: AppModel) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2, !hasSearched || q != lastSearched else { return }
        suggestions = (try? await app.extraction.suggestions(for: q)) ?? []
    }

    private var lastSearched: String { "" }
}

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @State private var model = SearchModel()

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.searchPath) {
            VStack(spacing: 0) {
                filterChips
                if model.isSearching {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if let error = model.error {
                    Spacer()
                    ErrorStateView(message: error) {
                        Task { await model.runSearch(app: app) }
                    }
                    Spacer()
                } else if let results = model.results {
                    resultList(results)
                } else if !model.suggestions.isEmpty {
                    suggestionList
                } else {
                    Spacer()
                    ContentUnavailableView("Search", systemImage: "magnifyingglass", description: Text("Search for videos, channels and playlists."))
                    Spacer()
                }
            }
            .navigationTitle("Search")
            .toolbar { StandardToolbar() }
            .searchable(text: $model.query, prompt: "Search YouTube")
            .onSubmit(of: .search) {
                model.hasSearched = false
                Task { await model.runSearch(app: app) }
            }
            .onChange(of: model.query) { _, _ in
                Task { await model.updateSuggestions(app: app) }
            }
            .onChange(of: model.filter) { _, _ in
                if model.hasSearched {
                    Task { await model.runSearch(app: app) }
                }
            }
            .navigationDestination(for: StreamItem.self) { VideoDetailView(stream: $0) }
            .navigationDestination(for: ChannelItem.self) { ChannelView(channel: $0) }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases) { filter in
                    Button {
                        model.filter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(model.filter == filter ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(model.filter == filter ? Theme.accent : Color(.secondarySystemFill), in: Capsule())
                            .foregroundStyle(model.filter == filter ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var suggestionList: some View {
        List(model.suggestions, id: \.self) { suggestion in
            Button {
                model.query = suggestion
                model.hasSearched = false
                Task { await model.runSearch(app: app) }
            } label: {
                Label(suggestion, systemImage: "magnifyingglass")
                    .foregroundStyle(.primary)
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func resultList(_ results: SearchResultKind) -> some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                switch results {
                case .streams(let streams):
                    ForEach(streams) { stream in
                        StreamCell(stream: stream)
                    }
                case .channels(let channels):
                    ForEach(channels) { channel in
                        NavigationLink(value: channel) {
                            ChannelRow(channel: channel)
                        }
                        .buttonStyle(.plain)
                    }
                case .playlists(let playlists):
                    ForEach(playlists) { playlist in
                        HStack(spacing: 12) {
                            AsyncThumbnail(url: playlist.thumbnailURL)
                                .frame(width: 140)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(playlist.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Text(playlist.author).font(.caption).foregroundStyle(.secondary)
                                Text(playlist.videoCountText ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
