import SwiftUI

@main
struct DsmMacApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("app.window.title") {
            RootView(model: model)
                .task {
                    model.load()
                }
        }
        .defaultSize(width: 1_260, height: 780)
        .windowResizability(.contentMinSize)
    }
}
