import SwiftUI

struct SubscriptionsView: View {
    @Environment(AppModel.self) private var app
    @State private var showHistory = false

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.subscriptionsPath) {
            Group {
                if app.subscriptions.isEmpty {
                    ContentUnavailableView("No subscriptions", systemImage: "person.2", description: Text("Subscribe to channels to see them here."))
                } else {
                    List {
                        ForEach(app.subscriptions) { channel in
                            NavigationLink(value: channel) {
                                ChannelRow(channel: channel)
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                let channel = app.subscriptions[index]
                                app.toggleSubscription(channel)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Subscriptions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                NavigationStack {
                    HistoryView()
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showHistory = false }
                            }
                        }
                }
            }
            .navigationDestination(for: ChannelItem.self) { ChannelView(channel: $0) }
            .navigationDestination(for: StreamItem.self) { VideoDetailView(stream: $0) }
        }
    }
}

struct HistoryView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.history.isEmpty {
                ContentUnavailableView("No history", systemImage: "clock", description: Text("Videos you watch will appear here."))
            } else {
                List {
                    ForEach(app.history) { stream in
                        NavigationLink(value: stream) {
                            HStack(spacing: 12) {
                                AsyncThumbnail(url: stream.thumbnailURL, videoId: stream.id)
                                    .frame(width: 130)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(stream.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(stream.author).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .onDelete { indexSet in
                        app.history.remove(atOffsets: indexSet)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear", role: .destructive) {
                    app.clearHistory()
                }
                .disabled(app.history.isEmpty)
            }
        }
        .navigationDestination(for: StreamItem.self) { VideoDetailView(stream: $0) }
    }
}
