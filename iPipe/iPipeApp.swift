import SwiftUI

@main
struct iPipeApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .preferredColorScheme(Theme.scheme(app.colorSchemeChoice))
        }
    }
}
