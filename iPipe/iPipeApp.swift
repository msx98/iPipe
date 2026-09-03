import SwiftUI

@main
struct iPipeApp: App {
    @State private var app = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .preferredColorScheme(Theme.scheme(app.colorSchemeChoice))
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        app.player.reactivateAudioSession()
                    }
                }
        }
    }
}
