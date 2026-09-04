import SwiftUI

/// Full-screen, focused video page. This is the single video detail experience
/// in the app — every entry point (trending, search, history, playlists,
/// channels, related videos) lands here so the top header is always the same:
/// Back + X on the leading edge, Downloads / History / Up Next on the trailing.
///
/// Collapsing (down-swipe or Back) dismisses the overlay entirely and hands off
/// to the shared `MiniPlayerBar` in `ContentView`, so there is only one
/// miniplayer style in the app and it never obscures scroll content.
struct VideoPlayerOverlay: View {
    @Environment(AppModel.self) private var app
    let stream: StreamItem
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black
                    .ignoresSafeArea(.container)

                NavigationStack {
                    VideoDetailView(
                        stream: stream,
                        onPlayerDragChanged: { dragOffset = max(0, $0) },
                        onPlayerDragEnded: endDrag,
                        playerDragOffset: dragOffset
                    )
                    .navigationDestination(for: ChannelItem.self) { ChannelView(channel: $0) }
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            Button { collapse() } label: {
                                Image(systemName: "chevron.left")
                            }
                            .accessibilityLabel("Back")
                            Button { close() } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel("Close")
                        }
                        StandardToolbar()
                    }
                }
                .tint(Theme.accent)
            }
        }
        .ignoresSafeArea(.container)
    }

    /// Dragging the video preview slides just the video downward with the finger
    /// (the top bar stays put); on release it collapses or springs back.
    private func endDrag(_ value: DragGesture.Value) {
        if value.translation.height > 140 || value.predictedEndTranslation.height > 120 {
            collapse()
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                dragOffset = 0
            }
        }
    }

    /// Dismiss the overlay; playback continues and the shared miniplayer takes
    /// over in the tab bar.
    private func collapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            dragOffset = 0
            app.focusedVideo = nil
        }
    }

    /// Closes the video and clears the queue entirely.
    private func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            app.focusedVideo = nil
            app.player.clearQueue()
        }
    }
}