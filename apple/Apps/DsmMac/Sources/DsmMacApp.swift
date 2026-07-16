import SwiftUI

@main
struct DsmMacApp: App {
    var body: some Scene {
        WindowGroup("app.window.title") {
            LoginView()
        }
        .windowResizability(.contentMinSize)
    }
}
