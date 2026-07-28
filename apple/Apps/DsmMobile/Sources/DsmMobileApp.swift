import SwiftUI

@main
struct DsmMobileApp: App {
    @State private var model = MobileAppModel()

    var body: some Scene {
        WindowGroup {
            MobileRootView(model: model)
        }
    }
}
