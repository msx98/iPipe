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
                        VideoDetailView(stream: stream)
                            .navigationDestination(for: StreamItem.self) { related in
                                VideoDetailView(stream: related)
                            }
                            .navigationDestination(for: ChannelItem.self) { ChannelView(channel: $0) }
                            .toolbar {
                                ToolbarItemGroup(placement: .topBarLeading) {
                                    Button { close() } label: {
                                        Image(systemName: "xmark")
                                    }
                                    Button { collapse() } label: {
                                        Image(systemName: "chevron.down")
                                    }
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

    private func collapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            expanded = false
        }
    }

    private func expand() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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