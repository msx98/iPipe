import SwiftUI

struct VideoPlayerOverlay: View {
    @Environment(AppModel.self) private var app
    let stream: StreamItem
    @State private var expanded = true

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
                        VideoDetailView(stream: stream, onSwipeDownToCollapse: collapse)
                            .navigationDestination(for: StreamItem.self) { related in
                                VideoDetailView(stream: related, onSwipeDownToCollapse: collapse)
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
                                                .onEnded { value in
                                                    if value.translation.height > 60 || value.predictedEndTranslation.height > 60 {
                                                        collapse()
                                                    }
                                                }
                                        )
                                }
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

    private func collapse() { expanded = false }
    private func expand() { expanded = true }
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
