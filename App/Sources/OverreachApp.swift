import SwiftUI

@main
struct OverreachApp: App {
    @State private var container = AppContainer.isUITesting ? AppContainer.uiTesting() : AppContainer.live()

    var body: some Scene {
        WindowGroup {
            RootView(container: container)
        }
    }
}
