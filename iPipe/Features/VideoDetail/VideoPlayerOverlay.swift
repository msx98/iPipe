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
                Color.black.opacity(0.25)
                    .ignoresSafeArea(.container)

                NavigationStack {
                    VideoDetailView(stream: stream)
                    .navigationDestination(for: ChannelItem.self) { ChannelView(channel: $0) }
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarLeading) {
                            Button { collapse() } label: {
                                Image(systemName: "chevron.left")
                            }
                            .accessibilityLabel("Back")
                            .tint(.white)
                            Button { close() } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel("Close")
                            .tint(.white)
                        }
                        StandardToolbar(color: .white, showsPiP: true)
                    }
                }
                .tint(Theme.accent)
                .offset(y: dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { dragOffset = max(0, $0.translation.height) }
                        .onEnded { endDrag($0) }
                )
            }
        }
        .ignoresSafeArea(.container)
    }

    /// Dragging down the whole overlay card (top bar + player + metadata + related)
    /// slides it as one unit toward the finger; on release it collapses past the
    /// threshold or springs back.
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