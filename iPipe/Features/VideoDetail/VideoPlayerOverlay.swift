import SwiftUI

struct VideoPlayerOverlay: View {
    @Environment(AppModel.self) private var app
    let stream: StreamItem
    @State private var expanded = true
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let bottomPad = 88 + geo.safeAreaInsets.bottom
            ZStack(alignment: .bottom) {
                Color.black
                    .ignoresSafeArea(.container)
                    .opacity(expanded ? 1 : 0)
                    .allowsHitTesting(expanded)

                if expanded {
                    NavigationStack {
                        VideoDetailView(
                            stream: stream,
                            onPlayerDragChanged: { dragOffset = max(0, $0) },
                            onPlayerDragEnded: endDrag,
                            playerDragOffset: dragOffset
                        )
                        .navigationDestination(for: StreamItem.self) { related in
                            VideoDetailView(
                                stream: related,
                                onPlayerDragChanged: { dragOffset = max(0, $0) },
                                onPlayerDragEnded: endDrag,
                                playerDragOffset: dragOffset
                            )
                        }
                        .navigationDestination(for: ChannelItem.self) { ChannelView(channel: $0) }
                        .toolbar {
                            ToolbarItemGroup(placement: .topBarLeading) {
                                Button { navigateBack() } label: {
                                    Image(systemName: "chevron.left")
                                }
                                .accessibilityLabel("Back")
                                Button { close() } label: {
                                    Image(systemName: "xmark")
                                }
                                .accessibilityLabel("Close and clear queue")
                            }
                            StandardToolbar()
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    MiniPlayerBar(onOpen: expand, onClose: close)
                        .padding(.horizontal, 12)
                        .padding(.bottom, bottomPad)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea(.container)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expanded)
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

    private func collapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            dragOffset = 0
            expanded = false
        }
    }

    /// `<` collapses to the mini player (soft back).
    private func navigateBack() {
        collapse()
    }

    private func expand() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            dragOffset = 0
            expanded = true
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            app.focusedVideo = nil
            app.player.clearQueue()
        }
    }
}