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
                            onPlayerDragChanged: { offset in
                                dragOffset = max(0, offset)
                            },
                            onPlayerDragEnded: finishDrag
                        )
                        .navigationDestination(for: StreamItem.self) { related in
                            VideoDetailView(
                                stream: related,
                                onPlayerDragChanged: { offset in
                                    dragOffset = max(0, offset)
                                },
                                onPlayerDragEnded: finishDrag
                            )
                        }
                        .navigationDestination(for: ChannelItem.self) { ChannelView(channel: $0) }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { close() } label: {
                                    Image(systemName: "xmark")
                                }
                            }
                            ToolbarItem(placement: .principal) {
                                DragHandle()
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 10)
                                            .onChanged { value in
                                                dragOffset = max(0, value.translation.height)
                                            }
                                            .onEnded(finishDrag)
                                    )
                            }
                        }
                    }
                    .offset(y: dragOffset)
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

    /// While the finger moves, the window slides with it. Pausing in the middle of
    /// a drag keeps the window mid-way; releasing lets it finish collapsing if
    /// pulled far enough, or spring back to the top otherwise.
    private func finishDrag(_ value: DragGesture.Value) {
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

    private func expand() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            dragOffset = 0
            expanded = true
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            app.focusedVideo = nil
            app.player.stop()
        }
    }
}

private struct DragHandle: View {
    var body: some View {
        Rectangle()
            .frame(width: 42, height: 5)
            .clipShape(Capsule())
            .foregroundStyle(.secondary)
    }
}