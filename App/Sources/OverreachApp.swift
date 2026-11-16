import SwiftUI

@main
struct OverreachApp: App {
    @State private var container = AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
